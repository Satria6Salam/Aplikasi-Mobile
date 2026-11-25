import '../services/ml_training_data.dart';
import 'indonesian_places.dart';

/// Satu kata yang dikoreksi otomatis, mis. "Nalang" -> "Malang".
class TextCorrection {
  const TextCorrection(this.from, this.to);

  final String from;
  final String to;

  @override
  String toString() => '$from → $to';

  @override
  bool operator ==(Object other) =>
      other is TextCorrection && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

enum _WordKind { keyword, place, brand, item }

class _Entry {
  const _Entry(this.word, this.kind, [this.weight = 1]);

  final String word;
  final _WordKind kind;
  final int weight;
}

/// Memperbaiki kata yang salah baca OCR dengan membandingkannya ke kamus
/// (kata kunci struk, nama kota dan jalan, merek, serta kosakata nama barang).
///
/// Kesalahan OCR yang khas dihitung lebih ringan daripada kesalahan acak:
/// huruf yang hilang ("uharto" -> "Muharto"), huruf yang mirip bentuknya
/// ("Nalang" -> "Malang", "Rcunding" -> "Rounding", "Taple" -> "Table"),
/// dan angka yang menyerupai huruf ("Tota1" -> "Total"). Kata yang sudah ada
/// di kamus tidak pernah diubah, dan bila dua kata kamus sama miripnya,
/// kata dibiarkan agar tidak salah koreksi.
class OcrTextCorrector {
  const OcrTextCorrector();

  // -------------------------------------------------------------- kamus

  static const List<String> _keywords = <String>[
    'total',
    'subtotal',
    'grand',
    'jumlah',
    'tunai',
    'cash',
    'change',
    'kembali',
    'kembalian',
    'rounding',
    'pembulatan',
    'discount',
    'diskon',
    'tax',
    'pajak',
    'service',
    'charge',
    'cashier',
    'kasir',
    'table',
    'meja',
    'purpose',
    'takeaway',
    'items',
    'item',
    'quantity',
    'price',
    'harga',
    'amount',
    'balance',
    'thank',
    'terima',
    'kasih',
    'payment',
    'pembayaran',
    'bayar',
    'debit',
    'credit',
    'kredit',
    'card',
    'kartu',
    'member',
    'point',
    'poin',
    'invoice',
    'faktur',
    'struk',
    'nota',
    'order',
    'date',
    'tanggal',
    'time',
    'waktu',
    'customer',
    'delivery',
    'whatsapp',
    'voucher',
    'promo',
    'hemat',
    'saving',
    'telp',
    'telepon',
    'alamat',
    'jalan',
    'kecamatan',
    'kabupaten',
    'kelurahan',
    'provinsi',
    'waiter',
    'server',
    'guest',
    'belanja',
    'tagihan',
    'akhir',
    'transaksi',
    'bill',
    'netto',
    'ongkir',
    'bonus',
    'cashback',
    'kirim',
    'online',
    'dine',
    'free',
    'minimum',
    'maximum',
    'berlaku',
    'barang',
    'produk',
    'pelanggan',
    'terimakasih',
    'selamat',
    'datang',
    'kunjungan',
    'kembali',
    'receipt',
    'cashless',
    'ewallet',
    'qris',
    'gopay',
    'shopeepay',
    'linkaja',
    'mandiri',
    'permata',
  ];

  static const List<String> _brands = <String>[
    'indomaret',
    'alfamart',
    'alfamidi',
    'lawson',
    'familymart',
    'superindo',
    'hypermart',
    'transmart',
    'carrefour',
    'giant',
    'matahari',
    'ramayana',
    'starbucks',
    'mcdonalds',
    'hokben',
    'solaria',
    'chatime',
    'wizzmie',
    'gacoan',
    'janji',
    'kenangan',
    'burger',
    'pizza',
    'bakery',
    'coffee',
    'kitchen',
    'restaurant',
    'restoran',
    'warung',
    'apotek',
    'pharmacy',
    'laundry',
    'bengkel',
    'toko',
    'mart',
    'minimarket',
    'supermarket',
    'elektronik',
    'kopi',
    'bakso',
    'geprek',
  ];

  /// Pasangan huruf yang sering tertukar oleh OCR (simetris).
  static const Set<String> _confusable = <String>{
    'nm',
    'ce',
    'co',
    'eo',
    'ao',
    'do',
    'li',
    'ij',
    'uv',
    'vy',
    'hb',
    'bp',
    'rn',
    'gq',
    'ac',
    'ou',
    'ae',
    'fl',
    'tl',
    'kx',
    'sz',
    'dq',
    'yv',
    'wv',
  };

  /// Dua huruf yang sering terbaca sebagai satu huruf, dan sebaliknya.
  static const Map<String, String> _shapeSwaps = <String, String>{
    'rn': 'm',
    'cl': 'd',
    'vv': 'w',
  };

  static final Map<String, _Entry> _dictionary = _buildDictionary();
  static final Map<String, _Entry> _itemVocabulary = _buildItemVocabulary();
  static final Map<String, String?> _cache = <String, String?>{};
  static final Map<String, String?> _itemCache = <String, String?>{};

  static Map<String, _Entry> _buildDictionary() {
    final Map<String, _Entry> map = <String, _Entry>{};
    for (final String w in _keywords) {
      map[w] = _Entry(w, _WordKind.keyword);
    }
    for (final String w in _brands) {
      map[w] = _Entry(w, _WordKind.brand);
    }
    for (final String place in <String>[
      ...IndonesianPlaces.cities,
      ...IndonesianPlaces.provinces,
    ]) {
      for (final String w in place.toLowerCase().split(' ')) {
        if (w.length >= 4) map[w] = _Entry(w, _WordKind.place);
      }
    }
    for (final String w in IndonesianPlaces.streets) {
      if (w.length >= 4) map.putIfAbsent(w, () => _Entry(w, _WordKind.place));
    }
    for (final String w in <String>[
      'utara',
      'selatan',
      'barat',
      'timur',
      'pusat'
    ]) {
      map[w] = _Entry(w, _WordKind.place);
    }
    return map;
  }

  static Map<String, _Entry> _buildItemVocabulary() {
    final Map<String, int> freq = <String, int>{};
    MlTrainingData.data.forEach((String _, List<String> names) {
      for (final String name in names) {
        for (final String w in name.toLowerCase().split(RegExp(r'[^a-z]+'))) {
          if (w.length >= 4) freq[w] = (freq[w] ?? 0) + 1;
        }
      }
    });
    return <String, _Entry>{
      for (final MapEntry<String, int> e in freq.entries)
        if (e.value >= 2) e.key: _Entry(e.key, _WordKind.item, e.value),
    };
  }

  // ----------------------------------------------------------- publik

  /// Menghilangkan tanda aksen: "Íce" -> "Ice".
  static String foldAccents(String text) {
    const String from = 'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖòóôõöÙÚÛÜùúûüÝýÿÑñÇç';
    const String to = 'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuYyyNnCc';
    if (!text.runes.any((int r) => r > 127)) return text;
    final StringBuffer out = StringBuffer();
    for (final int r in text.runes) {
      final String ch = String.fromCharCode(r);
      final int at = from.indexOf(ch);
      out.write(at >= 0 ? to[at] : ch);
    }
    return out.toString();
  }

  /// Memperbaiki kata kunci struk, nama kota/jalan, dan merek pada [line].
  /// Koreksi dicatat ke [sink] bila diberikan.
  ///
  /// [lenient] true (baris judul/alamat/header) juga memperbaiki SATU huruf
  /// yang hilang ("uharto" -> "Muharto", "Malng" -> "Malang"). Pada baris
  /// berisi harga (nama barang) hanya huruf yang mirip bentuknya yang
  /// diperbaiki, supaya nama menu seperti "Disko" tidak berubah jadi "Diskon".
  String correctLine(
    String line, {
    List<TextCorrection>? sink,
    bool lenient = true,
  }) {
    final String folded = foldAccents(line);
    return folded.replaceAllMapped(RegExp(r'[A-Za-z0-9]{3,}'), (Match m) {
      final String word = m.group(0)!;
      final String? fixed = _fixToken(word, lenient);
      if (fixed == null || fixed == word) return word;
      final TextCorrection c = TextCorrection(word, fixed);
      if (sink != null && !sink.contains(c)) sink.add(c);
      return fixed;
    });
  }

  /// Memperbaiki nama barang memakai kosakata data latih (lebih hati-hati
  /// daripada [correctLine] karena merek barang banyak yang tidak baku).
  String correctItemName(String name, {List<TextCorrection>? sink}) {
    final String folded = foldAccents(name);
    return folded.replaceAllMapped(RegExp(r'[A-Za-z]{4,}'), (Match m) {
      final String word = m.group(0)!;
      final String? fixed = _fixItemWord(word);
      if (fixed == null || fixed == word) return word;
      final TextCorrection c = TextCorrection(word, fixed);
      if (sink != null && !sink.contains(c)) sink.add(c);
      return fixed;
    });
  }

  /// "ICe" -> "Ice", "TEa" -> "Tea": huruf besar kedua yang menyelip pada
  /// kata berhuruf kecil adalah noda OCR (mis. dari aksen).
  static String normalizeCase(String word) {
    if (RegExp(r'^[A-Z]{2}[a-z]+$').hasMatch(word)) {
      return '${word[0]}${word.substring(1).toLowerCase()}';
    }
    return word;
  }

  /// Jarak sunting berbobot: huruf hilang/berlebih = 1, tertukar dengan huruf
  /// yang mirip bentuknya = 0,5, tertukar acak = 1, bertukar tempat = 1.
  static double distance(String a, String b) {
    final int n = a.length;
    final int m = b.length;
    final List<List<double>> d = List<List<double>>.generate(
      n + 1,
      (int i) => List<double>.filled(m + 1, 0),
    );
    for (int i = 0; i <= n; i++) {
      d[i][0] = i.toDouble();
    }
    for (int j = 0; j <= m; j++) {
      d[0][j] = j.toDouble();
    }
    for (int i = 1; i <= n; i++) {
      for (int j = 1; j <= m; j++) {
        final String x = a[i - 1];
        final String y = b[j - 1];
        final double sub = x == y
            ? 0
            : (_confusable.contains('$x$y') || _confusable.contains('$y$x')
                ? 0.5
                : 1);
        double best = d[i - 1][j - 1] + sub;
        if (d[i - 1][j] + 1 < best) best = d[i - 1][j] + 1;
        if (d[i][j - 1] + 1 < best) best = d[i][j - 1] + 1;
        if (i > 1 &&
            j > 1 &&
            a[i - 1] == b[j - 2] &&
            a[i - 2] == b[j - 1] &&
            d[i - 2][j - 2] + 1 < best) {
          best = d[i - 2][j - 2] + 1;
        }
        d[i][j] = best;
      }
    }
    return d[n][m];
  }

  // ---------------------------------------------------------- internal

  /// Batas jarak yang masih dianggap kesalahan OCR, menurut panjang kata.
  static double _limit(int length) {
    if (length <= 5) return 0.5;
    if (length <= 8) return 1.0;
    return 1.5;
  }

  static const Map<String, List<String>> _digitToLetters =
      <String, List<String>>{
    '0': <String>['o'],
    '1': <String>['l', 'i'],
    '5': <String>['s'],
    '8': <String>['b'],
  };

  String? _fixToken(String token, bool lenient) {
    final String key = '${lenient ? 'L' : 'S'}:$token';
    if (_cache.containsKey(key)) return _cache[key];
    final String? result = _compute(token, lenient);
    _cache[key] = result;
    return result;
  }

  /// True bila [word] adalah [full] yang kehilangan tepat satu huruf.
  static bool _missingOneLetter(String word, String full) {
    if (word.length != full.length - 1) return false;
    for (int i = 0; i < full.length; i++) {
      if ('${full.substring(0, i)}${full.substring(i + 1)}' == word) {
        return true;
      }
    }
    return false;
  }

  String? _compute(String token, bool lenient) {
    final String lower = token.toLowerCase();
    final bool hasDigit = RegExp(r'\d').hasMatch(token);
    final int letters = RegExp(r'[A-Za-z]').allMatches(token).length;

    // Angka yang menyerupai huruf di dalam kata ("Tota1", "T0tal").
    if (hasDigit) {
      if (letters < 3) return null;
      for (final String variant in _digitVariants(lower)) {
        final _Entry? hit = _dictionary[variant];
        if (hit != null) return _styled(token, hit);
      }
      return null;
    }

    if (_dictionary.containsKey(lower)) return null; // sudah benar
    if (lower.length < 4) return null;

    // Dua huruf yang menyerupai satu huruf: "Kernbali" -> "Kembali".
    for (final MapEntry<String, String> shape in _shapeSwaps.entries) {
      if (!lower.contains(shape.key)) continue;
      final _Entry? hit = _dictionary[lower.replaceAll(shape.key, shape.value)];
      if (hit != null) return _styled(token, hit);
    }

    _Entry? best;
    double bestCost = double.infinity;
    bool tie = false;
    for (final _Entry e in _dictionary.values) {
      if ((e.word.length - lower.length).abs() > 2) continue;
      // Nama jalan umum yang pendek terlalu rawan salah koreksi.
      if (e.kind == _WordKind.place && e.word.length < 6) continue;
      double cost = distance(lower, e.word);
      // Satu huruf hilang dihitung murah, tetapi hanya pada baris judul/alamat
      // dan untuk kata yang cukup panjang agar tidak ambigu.
      final bool distinctiveKeyword =
          e.kind == _WordKind.keyword && e.word.length >= 7;
      if ((lenient || distinctiveKeyword) &&
          e.word.length >= 6 &&
          _missingOneLetter(lower, e.word)) {
        cost = 0.5;
      } else if (cost > 0.5 && e.word.length <= 8) {
        continue; // Perbedaan acak tidak dianggap salah baca OCR.
      }
      if (cost > _limit(e.word.length)) continue;
      if (cost < bestCost - 1e-9) {
        best = e;
        bestCost = cost;
        tie = false;
      } else if ((cost - bestCost).abs() < 1e-9 && best?.word != e.word) {
        tie = true;
      }
    }
    if (best == null || tie) return null;
    return _styled(token, best);
  }

  List<String> _digitVariants(String lower) {
    List<String> variants = <String>[''];
    for (int i = 0; i < lower.length; i++) {
      final String ch = lower[i];
      final List<String> options = _digitToLetters[ch] ?? <String>[ch];
      variants = <String>[
        for (final String v in variants)
          for (final String o in options) '$v$o',
      ];
      if (variants.length > 16) return <String>[];
    }
    return variants;
  }

  String? _fixItemWord(String word) {
    if (_itemCache.containsKey(word)) return _itemCache[word];
    final String lower = word.toLowerCase();
    String? result;
    // Kata pendek (mis. "AMEL", nama obat) terlalu sering nama merek yang tidak
    // baku; hanya kata sepanjang 6 huruf ke atas yang diperbaiki.
    if (!_itemVocabulary.containsKey(lower) &&
        !_dictionary.containsKey(lower) &&
        lower.length >= 6) {
      _Entry? best;
      double bestCost = double.infinity;
      bool tie = false;
      // Satu huruf mirip bentuknya (c/e, n/m) boleh tertukar; satu huruf boleh
      // hilang hanya pada kata umum yang panjang. Dua kesalahan sekaligus tidak
      // dikoreksi: nama barang sering tidak baku ("Rajalele" bukan "Rojolele").
      for (final _Entry e in _itemVocabulary.values) {
        if ((e.word.length - lower.length).abs() > 1) continue;
        double cost = distance(lower, e.word);
        if (e.weight >= 3 &&
            e.word.length >= 6 &&
            _missingOneLetter(lower, e.word)) {
          cost = 0.5;
        }
        if (cost > 0.5) continue;
        if (cost < bestCost - 1e-9 ||
            ((cost - bestCost).abs() < 1e-9 &&
                best != null &&
                e.weight > best.weight * 3)) {
          best = e;
          bestCost = cost;
          tie = false;
        } else if ((cost - bestCost).abs() < 1e-9 && best?.word != e.word) {
          tie = true;
        }
      }
      if (best != null && !tie) result = _styled(word, best);
    }
    _itemCache[word] = result;
    return result;
  }

  /// Menyamakan gaya huruf hasil koreksi dengan kata aslinya.
  String _styled(String original, _Entry entry) {
    final String w = entry.word;
    final bool upper = original == original.toUpperCase() &&
        RegExp(r'[A-Z]').hasMatch(original);
    if (upper) return w.toUpperCase();
    final bool title = original.isNotEmpty &&
        original[0] == original[0].toUpperCase() &&
        RegExp(r'[A-Z]').hasMatch(original[0]);
    final bool proper =
        entry.kind == _WordKind.place || entry.kind == _WordKind.brand || title;
    return proper ? '${w[0].toUpperCase()}${w.substring(1)}' : w;
  }
}
