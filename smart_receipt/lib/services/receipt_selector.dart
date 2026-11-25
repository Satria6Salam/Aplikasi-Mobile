import '../core/constants/db_constants.dart';
import 'parsing_service.dart';

/// Satu hasil baca struk: teks OCR beserta hasil parsing-nya.
class ReceiptReading {
  const ReceiptReading({
    required this.rawText,
    required this.parsed,
    this.fromEnhancedImage = false,
  });

  final String rawText;
  final ParsedReceiptData parsed;

  /// True bila teks dibaca dari foto yang sudah diperjelas.
  final bool fromEnhancedImage;
}

/// Menilai hasil baca struk dan memilih yang terbaik di antara hasil dari
/// foto asli dan foto yang sudah diperjelas.
class ReceiptSelector {
  const ReceiptSelector();

  /// Toleransi selisih jumlah barang terhadap total struk.
  static const double _sumTolerance = 0.01;
  static const int _maxScoredItems = 20;
  static final RegExp _alphanumeric = RegExp(r'[A-Za-z0-9]');

  /// True bila jumlah harga barang sama dengan yang diharapkan: subtotal bila
  /// struk memuat pajak/layanan/pembulatan, selain itu total struk.
  bool isConsistent(ParsedReceiptData parsed) {
    final double? target = parsed.expectedItemsTotal;
    if (target == null || target <= 0 || parsed.items.isEmpty) return false;
    return parsed.itemsMatch(parsed.itemsTotal, relative: _sumTolerance);
  }

  /// True bila semua data utama terbaca dan saling cocok, sehingga foto
  /// tidak perlu diperjelas lalu dibaca ulang.
  bool isComplete(ParsedReceiptData parsed) {
    return parsed.merchantName != null &&
        parsed.transactionDate != null &&
        parsed.totalFromKeyword &&
        isConsistent(parsed);
  }

  /// Makin tinggi makin lengkap dan makin dapat dipercaya.
  double score(ReceiptReading reading) {
    final ParsedReceiptData parsed = reading.parsed;
    final int items = parsed.items.length > _maxScoredItems
        ? _maxScoredItems
        : parsed.items.length;
    double value = items * 3.0;
    if (parsed.totalAmount != null) value += 4;
    if (parsed.transactionDate != null) value += 2;
    if (parsed.merchantName != null) value += 1;
    if (isConsistent(parsed)) value += 6;
    final int characters = _alphanumeric.allMatches(reading.rawText).length;
    value += characters >= 200 ? 5 : characters / 40;
    return value;
  }

  /// Alamat yang lebih lengkap (komponen terbanyak, lalu keyakinan tertinggi).
  StoreAddress _betterAddress(StoreAddress first, StoreAddress second) {
    if (first.isEmpty) return second;
    if (second.isEmpty) return first;
    int parts(StoreAddress a) => <Object?>[
          a.street,
          a.village,
          a.district,
          a.city,
          a.postalCode,
        ].where((Object? v) => v != null).length;
    final int byParts = parts(first).compareTo(parts(second));
    if (byParts != 0) return byParts > 0 ? first : second;
    return first.confidence >= second.confidence ? first : second;
  }

  /// Memilih bacaan dengan nilai tertinggi (foto asli menang bila seri),
  /// lalu melengkapi data utama yang kosong dari bacaan lainnya.
  ReceiptReading choose(ReceiptReading original, ReceiptReading? enhanced) {
    if (enhanced == null) return original;
    final bool useEnhanced = score(enhanced) > score(original);
    final ReceiptReading best = useEnhanced ? enhanced : original;
    final ReceiptReading other = useEnhanced ? original : enhanced;

    final ParsedReceiptData a = best.parsed;
    final ParsedReceiptData b = other.parsed;
    final String? merchant = a.merchantName ?? b.merchantName;
    final DateTime? date = a.transactionDate ?? b.transactionDate;
    final double? total = a.totalAmount ?? b.totalAmount;
    final bool totalFromKeyword =
        a.totalAmount != null ? a.totalFromKeyword : b.totalFromKeyword;
    final List<ParsedItem> items = a.items.isNotEmpty ? a.items : b.items;
    // Rincian angka (subtotal, pajak, pembulatan) diambil dari bacaan yang
    // memuat total, supaya semuanya berasal dari satu foto.
    final ParsedReceiptData summarySource = a.totalAmount != null ? a : b;
    final List<TextCorrection> corrections = <TextCorrection>[
      ...a.corrections,
      for (final TextCorrection c in b.corrections)
        if (!a.corrections.contains(c)) c,
    ];
    // Alamat dari bacaan yang lebih lengkap; bila kosong, dari bacaan lain.
    // (Sebelumnya alamat ikut hilang tiap kali foto diperjelas dan dibaca ulang.)
    final StoreAddress address = _betterAddress(a.address, b.address);

    final int found = <Object?>[merchant, date, total]
        .where((Object? value) => value != null)
        .length;
    final String status = found == 3
        ? ParsingStatus.success
        : (found == 0 ? ParsingStatus.failed : ParsingStatus.partial);

    return ReceiptReading(
      rawText: best.rawText,
      parsed: ParsedReceiptData(
        merchantName: merchant,
        transactionDate: date,
        totalAmount: total,
        items: items,
        status: status,
        totalFromKeyword: totalFromKeyword,
        address: address,
        subtotal: summarySource.subtotal,
        taxAmount: summarySource.taxAmount,
        taxLabel: summarySource.taxLabel,
        serviceAmount: summarySource.serviceAmount,
        discountAmount: summarySource.discountAmount,
        roundingAmount: summarySource.roundingAmount,
        itemsTarget: summarySource.itemsTarget,
        itemsCount: a.itemsCount ?? b.itemsCount,
        corrections: corrections,
      ),
      fromEnhancedImage: best.fromEnhancedImage,
    );
  }
}
