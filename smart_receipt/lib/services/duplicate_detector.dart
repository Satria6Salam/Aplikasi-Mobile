import '../data/models/transaction_item_model.dart';
import '../data/models/transaction_model.dart';
import '../data/repositories/transaction_repository.dart';

/// Transaksi lama yang mirip dengan struk yang sedang disimpan.
class DuplicateMatch {
  const DuplicateMatch({
    required this.transaction,
    required this.confidence,
    required this.reasons,
    this.hasItems = false,
  });

  /// True bila transaksi lama itu sudah punya rincian barang.
  final bool hasItems;

  /// True bila transaksi lama berasal dari Scan QRIS dan belum punya rincian
  /// barang: struk yang baru dipindai dapat MELENGKAPINYA, bukan membuat
  /// transaksi ganda.
  bool get canAttachReceipt => transaction.isQris && !hasItems;

  final TransactionModel transaction;

  /// 0..1; di atas 0,85 hampir pasti struk yang sama.
  final double confidence;

  /// Alasan kemiripan untuk ditampilkan, mis. "Toko sama", "80% barang sama".
  final List<String> reasons;

  bool get isLikely => confidence >= 0.85;
}

/// Mendeteksi struk yang kemungkinan sudah pernah dicatat (mis. struk yang
/// sama dipindai dua kali).
///
/// Syarat dasar: tanggal sama dan total sama (selisih maksimal Rp 1). Dari
/// situ dinilai kemiripan toko dan barangnya:
/// - toko mirip: dianggap kembar; bila barangnya juga sama, hampir pasti.
/// - toko beda (mis. OCR salah baca nama) tetapi ≥60% barang sama: tetap
///   ditandai.
/// - tanggal dan total kebetulan sama pada toko dan barang berbeda: tidak
///   ditandai, agar tidak mengganggu.
class DuplicateDetector {
  const DuplicateDetector(this._repository);

  final TransactionRepository _repository;

  Future<List<DuplicateMatch>> find({
    required int userId,
    required DateTime date,
    required double total,
    required String merchantName,
    required List<String> itemNames,
  }) async {
    final List<TransactionModel> candidates =
        await _repository.findSameDayAmount(userId, date, total);
    if (candidates.isEmpty) return const <DuplicateMatch>[];

    final List<DuplicateMatch> matches = <DuplicateMatch>[];
    for (final TransactionModel t in candidates) {
      final bool merchantOk = merchantsSimilar(merchantName, t.merchantName);

      double overlap = 0;
      bool hasItems = false;
      final int? id = t.id;
      if (id != null && itemNames.isNotEmpty) {
        try {
          final List<TransactionItemModel> stored =
              await _repository.getItems(id);
          hasItems = stored.isNotEmpty;
          overlap = itemOverlap(
            itemNames,
            stored.map((TransactionItemModel i) => i.name).toList(),
          );
        } catch (_) {
          // Rincian barang tidak terbaca: nilai dari toko saja.
        }
      }

      double confidence;
      if (merchantOk) {
        confidence = 0.7 + 0.3 * overlap;
      } else if (overlap >= 0.6) {
        confidence = 0.55 + 0.3 * overlap;
      } else {
        continue;
      }
      matches.add(
        DuplicateMatch(
          transaction: t,
          hasItems: hasItems,
          confidence: double.parse(confidence.toStringAsFixed(2)),
          reasons: <String>[
            if (merchantOk) 'Toko sama',
            'Tanggal sama',
            'Total sama',
            if (overlap >= 0.3) '${(overlap * 100).round()}% barang sama',
          ],
        ),
      );
    }
    matches.sort((DuplicateMatch a, DuplicateMatch b) =>
        b.confidence.compareTo(a.confidence));
    return matches;
  }

  // ---------------------------------------------------------------- toko

  static String _key(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// True bila dua nama toko kemungkinan sama: persis, saling memuat,
  /// kata-katanya banyak yang sama, atau hanya beda 1-2 huruf (salah baca OCR).
  static bool merchantsSimilar(String a, String b) {
    final String ka = _key(a);
    final String kb = _key(b);
    if (ka.isEmpty || kb.isEmpty) return false;
    if (ka == kb) return true;

    final String shorter = ka.length <= kb.length ? ka : kb;
    final String longer = ka.length <= kb.length ? kb : ka;
    if (shorter.length >= 4 && longer.contains(shorter)) return true;

    final Set<String> ta = ka.split(' ').toSet();
    final Set<String> tb = kb.split(' ').toSet();
    final int common = ta.intersection(tb).length;
    final int union = ta.union(tb).length;
    if (union > 0 && common / union >= 0.5) return true;

    final String ca = ka.replaceAll(' ', '');
    final String cb = kb.replaceAll(' ', '');
    return ca.length >= 6 &&
        cb.length >= 6 &&
        (ca.length - cb.length).abs() <= 2 &&
        _levenshtein(ca, cb) <= 2;
  }

  // -------------------------------------------------------------- barang

  /// Porsi barang yang sama di antara dua daftar (0..1).
  static double itemOverlap(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final List<String> ka =
        a.map(_key).where((String s) => s.isNotEmpty).toList();
    final List<String> kb =
        b.map(_key).where((String s) => s.isNotEmpty).toList();
    if (ka.isEmpty || kb.isEmpty) return 0;

    final List<String> pool = List<String>.of(kb);
    int matched = 0;
    for (final String item in ka) {
      final int at = pool.indexWhere(
        (String other) =>
            other == item ||
            (item.length >= 4 && other.contains(item)) ||
            (other.length >= 4 && item.contains(other)) ||
            (item.length >= 6 &&
                other.length >= 6 &&
                (item.length - other.length).abs() <= 2 &&
                _levenshtein(item, other) <= 2),
      );
      if (at >= 0) {
        matched++;
        pool.removeAt(at);
      }
    }
    final int bigger = ka.length > kb.length ? ka.length : kb.length;
    return matched / bigger;
  }

  static int _levenshtein(String a, String b) {
    final List<int> prev = List<int>.generate(b.length + 1, (int i) => i);
    final List<int> cur = List<int>.filled(b.length + 1, 0);
    for (int i = 1; i <= a.length; i++) {
      cur[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final int cost = a[i - 1] == b[j - 1] ? 0 : 1;
        final int del = prev[j] + 1;
        final int ins = cur[j - 1] + 1;
        final int sub = prev[j - 1] + cost;
        cur[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      prev.setAll(0, cur);
    }
    return prev[b.length];
  }
}
