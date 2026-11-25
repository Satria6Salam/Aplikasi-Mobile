import '../data/models/purchase_record_model.dart';

/// Arah perubahan harga pembelian terakhir.
enum PriceTrend { up, down, flat, unknown }

/// Perubahan harga pembelian terakhir dibanding pembelian sebelumnya.
class PriceChange {
  const PriceChange({
    required this.percent,
    required this.previousPrice,
    required this.sameStore,
    required this.trend,
  });

  /// Pecahan perubahan (0,12 = naik 12%).
  final double percent;
  final double previousPrice;

  /// True bila pembanding adalah pembelian sebelumnya di toko yang sama.
  final bool sameStore;
  final PriceTrend trend;
}

/// Ringkasan harga sebuah barang di satu toko.
class StorePrice {
  const StorePrice({
    required this.merchant,
    required this.purchases,
    required this.average,
    required this.lowest,
    required this.highest,
    required this.latestPrice,
    required this.latestDate,
  });

  final String merchant;
  final int purchases;
  final double average;
  final double lowest;
  final double highest;
  final double latestPrice;
  final DateTime latestDate;
}

/// Satu barang yang dapat dibandingkan: seluruh riwayat pembeliannya.
class ProductPrices {
  ProductPrices({
    required this.key,
    required this.name,
    required this.purchases,
    required this.stores,
  });

  /// Nama ternormalisasi (kunci pengelompokan).
  final String key;

  /// Nama tampilan: penulisan yang paling sering muncul di struk.
  final String name;

  /// Riwayat pembelian, terlama lebih dulu.
  final List<PurchaseRecord> purchases;

  /// Ringkasan per toko, harga rata-rata termurah lebih dulu.
  final List<StorePrice> stores;

  int get count => purchases.length;
  int get storeCount => stores.length;
  PurchaseRecord get latest => purchases.last;
  PurchaseRecord get first => purchases.first;
  String? get categoryName => latest.categoryName;

  double get lowest => purchases
      .map((PurchaseRecord p) => p.unitPrice)
      .reduce((double a, double b) => a < b ? a : b);
  double get highest => purchases
      .map((PurchaseRecord p) => p.unitPrice)
      .reduce((double a, double b) => a > b ? a : b);
  double get average =>
      purchases.fold<double>(
          0, (double s, PurchaseRecord p) => s + p.unitPrice) /
      purchases.length;

  /// Pembelian dengan harga satuan terendah (yang terbaru bila seri).
  PurchaseRecord get cheapestPurchase => purchases.reduce(
        (PurchaseRecord a, PurchaseRecord b) =>
            b.unitPrice <= a.unitPrice ? b : a,
      );

  /// True bila barang ini dibeli di dua toko atau lebih.
  bool get isComparable => stores.length >= 2;

  StorePrice? get cheapestStore => isComparable ? stores.first : null;
  StorePrice? get priciestStore => isComparable ? stores.last : null;

  /// Penghematan bila selalu membeli di toko termurah (pecahan dari harga
  /// rata-rata toko termahal); null bila hanya satu toko.
  double? get potentialSaving {
    final StorePrice? cheap = cheapestStore;
    final StorePrice? dear = priciestStore;
    if (cheap == null || dear == null || dear.average <= 0) return null;
    return (dear.average - cheap.average) / dear.average;
  }

  /// Perubahan harga pembelian terakhir; null bila baru sekali dibeli.
  PriceChange? get latestChange {
    if (purchases.length < 2) return null;
    final PurchaseRecord last = purchases.last;
    final String store = PriceComparisonService.storeKey(last.merchantName);

    PurchaseRecord? previous;
    bool sameStore = false;
    for (int i = purchases.length - 2; i >= 0; i--) {
      if (PriceComparisonService.storeKey(purchases[i].merchantName) == store) {
        previous = purchases[i];
        sameStore = true;
        break;
      }
    }
    previous ??= purchases[purchases.length - 2];
    if (previous.unitPrice <= 0) return null;

    final double percent =
        (last.unitPrice - previous.unitPrice) / previous.unitPrice;
    final PriceTrend trend = percent > 0.02
        ? PriceTrend.up
        : (percent < -0.02 ? PriceTrend.down : PriceTrend.flat);
    return PriceChange(
      percent: percent,
      previousPrice: previous.unitPrice,
      sameStore: sameStore,
      trend: trend,
    );
  }
}

/// Mengelompokkan barang yang sama dari berbagai struk lalu menghitung
/// perbandingan harga antar toko dan perubahannya dari waktu ke waktu.
///
/// Nama barang di struk jarang persis sama ("AQUA 600ML", "Aqua 600 ml",
/// "AQUA 600 ML BTL"), jadi nama dinormalisasi dan dicocokkan dengan toleransi
/// salah ketik. Ukuran (600ml, 1kg) membedakan produk: air 600ml tidak
/// dibandingkan dengan air 1500ml.
class PriceComparisonService {
  const PriceComparisonService();

  static const Map<String, String> _unitAlias = <String, String>{
    'ltr': 'l',
    'liter': 'l',
    'lt': 'l',
    'gr': 'g',
    'gram': 'g',
    'pc': 'pcs',
    'sct': 'sachet',
    'btl': 'botol',
  };

  static final RegExp _sizeWithUnit = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(ml|ltr|liter|lt|l|gr|gram|g|kg|mg|pcs|pc|sct|sachet|btl|botol|bks|pak|pack|box|dus|lsn|roll|m|cm)\b',
  );
  static final RegExp _hasDigit = RegExp(r'\d');
  static final RegExp _sizeToken = RegExp(
    r'^\d+(?:\.\d+)?(?:ml|l|g|kg|mg|pcs|sachet|botol|bks|pak|pack|box|dus|lsn|roll|m|cm)$',
  );

  /// Kunci toko: huruf kecil tanpa tanda baca.
  static String storeKey(String merchant) => merchant
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// "AQUA 600 ML" -> "aqua 600ml"; "Susu UHT 1,5 Ltr" -> "susu uht 1.5l".
  static String normalize(String name) {
    String s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9., ]'), ' ');
    s = s.replaceAllMapped(_sizeWithUnit, (Match m) {
      final String number = (m.group(1) ?? '').replaceAll(',', '.');
      final String unit = m.group(2) ?? '';
      return ' $number${_unitAlias[unit] ?? unit} ';
    });
    s = s.replaceAll(RegExp(r'(?<!\d)[.,]|[.,](?!\d)'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<String> _tokens(String normalized) => normalized
      .split(' ')
      .where((String t) => t.isNotEmpty && t != 'the')
      .toList();

  static Set<String> _sizes(List<String> tokens) =>
      tokens.where(_sizeToken.hasMatch).toSet();

  /// True bila dua nama (sudah dinormalisasi) adalah barang yang sama.
  static bool sameProduct(String a, String b) {
    if (a == b) return true;
    return _sameTokens(_tokens(a), _tokens(b));
  }

  static bool _sameTokens(List<String> ta, List<String> tb) {
    if (ta.isEmpty || tb.isEmpty) return false;

    // Ukuran berbeda = produk berbeda.
    final Set<String> sa = _sizes(ta);
    final Set<String> sb = _sizes(tb);
    if (sa.isNotEmpty &&
        sb.isNotEmpty &&
        (sa.length != sb.length || !sa.containsAll(sb))) {
      return false;
    }

    final List<String> pool = List<String>.of(tb);
    int matched = 0;
    for (final String x in ta) {
      final int at = pool.indexWhere((String y) => _tokenEqual(x, y));
      if (at >= 0) {
        matched++;
        pool.removeAt(at);
      }
    }
    final int union = ta.length + tb.length - matched;
    return union > 0 && matched / union >= 0.75;
  }

  static bool _tokenEqual(String x, String y) {
    if (x == y) return true;
    // Salah ketik satu huruf pada kata cukup panjang ("gorang" ~ "goreng").
    if (x.length < 5 || y.length < 5) return false;
    if (_hasDigit.hasMatch(x) || _hasDigit.hasMatch(y)) return false;
    return (x.length - y.length).abs() <= 1 && _levenshtein(x, y) <= 1;
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

  /// Mengelompokkan [records] menjadi daftar barang. Pembelian dengan harga
  /// satuan tidak valid (≤ 0) diabaikan. Hasil: paling sering dibeli dulu.
  List<ProductPrices> compare(List<PurchaseRecord> records) {
    // 1. Kelompokkan per nama ternormalisasi yang persis sama.
    final Map<String, List<PurchaseRecord>> byKey =
        <String, List<PurchaseRecord>>{};
    for (final PurchaseRecord r in records) {
      if (r.unitPrice <= 0) continue;
      final String key = normalize(r.itemName);
      if (key.isEmpty) continue;
      byKey.putIfAbsent(key, () => <PurchaseRecord>[]).add(r);
    }

    // 2. Gabungkan nama yang mirip; nama yang paling sering jadi wakil.
    final List<String> keys = byKey.keys.toList()
      ..sort((String a, String b) {
        final int byCount = byKey[b]!.length.compareTo(byKey[a]!.length);
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    final List<String> representatives = <String>[];
    final Map<String, List<String>> tokenCache = <String, List<String>>{
      for (final String key in keys) key: _tokens(key),
    };
    final Map<String, List<PurchaseRecord>> clusters =
        <String, List<PurchaseRecord>>{};
    for (final String key in keys) {
      String? home;
      for (final String rep in representatives) {
        if (_sameTokens(tokenCache[rep]!, tokenCache[key]!)) {
          home = rep;
          break;
        }
      }
      if (home == null) {
        representatives.add(key);
        home = key;
      }
      clusters.putIfAbsent(home, () => <PurchaseRecord>[]).addAll(byKey[key]!);
    }

    // 3. Ringkas tiap kelompok.
    final List<ProductPrices> products = <ProductPrices>[
      for (final MapEntry<String, List<PurchaseRecord>> e in clusters.entries)
        _summarize(e.key, e.value),
    ];
    products.sort((ProductPrices a, ProductPrices b) {
      final int byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      return b.latest.date.compareTo(a.latest.date);
    });
    return products;
  }

  ProductPrices _summarize(String key, List<PurchaseRecord> records) {
    final List<PurchaseRecord> sorted = List<PurchaseRecord>.of(records)
      ..sort((PurchaseRecord a, PurchaseRecord b) {
        final int byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.itemId.compareTo(b.itemId);
      });

    // Nama tampilan: penulisan asli yang paling sering muncul.
    final Map<String, int> spelled = <String, int>{};
    for (final PurchaseRecord r in sorted) {
      spelled.update(r.itemName.trim(), (int n) => n + 1, ifAbsent: () => 1);
    }
    final String name = spelled.entries
        .reduce((MapEntry<String, int> a, MapEntry<String, int> b) =>
            b.value > a.value ? b : a)
        .key;

    // Ringkasan per toko.
    final Map<String, List<PurchaseRecord>> byStore =
        <String, List<PurchaseRecord>>{};
    for (final PurchaseRecord r in sorted) {
      byStore
          .putIfAbsent(storeKey(r.merchantName), () => <PurchaseRecord>[])
          .add(r);
    }
    final List<StorePrice> stores = <StorePrice>[
      for (final List<PurchaseRecord> list in byStore.values)
        StorePrice(
          merchant: list.last.merchantName,
          purchases: list.length,
          average: list.fold<double>(
                  0, (double s, PurchaseRecord p) => s + p.unitPrice) /
              list.length,
          lowest: list
              .map((PurchaseRecord p) => p.unitPrice)
              .reduce((double a, double b) => a < b ? a : b),
          highest: list
              .map((PurchaseRecord p) => p.unitPrice)
              .reduce((double a, double b) => a > b ? a : b),
          latestPrice: list.last.unitPrice,
          latestDate: list.last.date,
        ),
    ]..sort((StorePrice a, StorePrice b) => a.average.compareTo(b.average));

    return ProductPrices(
      key: key,
      name: name,
      purchases: sorted,
      stores: stores,
    );
  }

  /// Kalimat ringkasan yang mudah dipahami untuk sebuah barang.
  List<String> insights(
    ProductPrices p, {
    required String Function(double) money,
  }) {
    final List<String> lines = <String>[];

    final StorePrice? cheap = p.cheapestStore;
    final StorePrice? dear = p.priciestStore;
    final double? saving = p.potentialSaving;
    if (cheap != null && dear != null && saving != null) {
      if (saving >= 0.03) {
        lines.add(
          'Termurah di ${cheap.merchant} (rata-rata ${money(cheap.average)}), '
          '${(saving * 100).round()}% lebih murah dari ${dear.merchant} '
          '(${money(dear.average)}).',
        );
      } else {
        lines.add('Harganya hampir sama di semua toko.');
      }
    } else {
      lines.add(
        'Baru dibeli di ${p.stores.first.merchant}. Beli di toko lain untuk '
        'membandingkan harga.',
      );
    }

    final PriceChange? change = p.latestChange;
    if (change != null) {
      final String where =
          change.sameStore ? 'di toko yang sama' : 'sebelumnya (toko lain)';
      final String pct = '${(change.percent.abs() * 100).round()}%';
      switch (change.trend) {
        case PriceTrend.up:
          lines.add(
              'Harga terakhir naik $pct dari ${money(change.previousPrice)} $where.');
        case PriceTrend.down:
          lines.add(
              'Harga terakhir turun $pct dari ${money(change.previousPrice)} $where.');
        case PriceTrend.flat:
          lines.add('Harga terakhir stabil dibanding pembelian $where.');
        case PriceTrend.unknown:
          break;
      }
    }

    if (p.count >= 3 && p.latest.unitPrice > p.average * 1.1) {
      lines.add('Harga terakhir di atas rata-rata Anda (${money(p.average)}).');
    }
    return lines;
  }
}
