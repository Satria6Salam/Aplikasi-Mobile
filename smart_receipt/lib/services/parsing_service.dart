import '../core/constants/db_constants.dart';
import 'indonesian_places.dart';
import 'ocr_text_corrector.dart';
import 'store_address_extractor.dart';

export 'ocr_text_corrector.dart' show TextCorrection;
export 'store_address_extractor.dart' show StoreAddress;

/// Satu barang hasil pembacaan struk.
class ParsedItem {
  const ParsedItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.alternative,
    this.quantityKnown = true,
  });

  /// False bila jumlahnya hanya diasumsikan 1 karena baris tidak
  /// mencantumkannya (mis. angka di depan nama terpotong OCR).
  final bool quantityKnown;

  final String name;
  final double quantity;
  final double unitPrice;
  final double totalPrice;

  /// Tafsir lain untuk baris yang angkanya ambigu: struk "Roti 2 12.000"
  /// bisa berarti 12.000 adalah subtotal (tafsir utama) atau harga satuan
  /// (tafsir alternatif, total 24.000). Total struk menentukan mana yang benar.
  final ParsedItem? alternative;

  /// True bila angka pada baris ini bisa ditafsirkan dua cara.
  bool get isAmbiguous => alternative != null;

  /// Salinan dengan jumlah [qty]; total harga tetap, harga satuan dihitung ulang.
  ParsedItem withQuantity(double qty) => ParsedItem(
        name: name,
        quantity: qty,
        unitPrice: totalPrice / qty,
        totalPrice: totalPrice,
      );
}

/// Hasil Smart Parsing dari teks mentah struk.
/// Setiap variabel bernilai null bila tidak ditemukan (UC-03).
class ParsedReceiptData {
  const ParsedReceiptData({
    this.merchantName,
    this.transactionDate,
    this.totalAmount,
    this.items = const <ParsedItem>[],
    required this.status,
    this.totalFromKeyword = true,
    this.address = StoreAddress.empty,
    this.subtotal,
    this.taxAmount,
    this.taxLabel,
    this.serviceAmount,
    this.discountAmount,
    this.roundingAmount,
    this.itemsTarget,
    this.itemsCount,
    this.corrections = const <TextCorrection>[],
  });

  /// Subtotal barang pada struk (sebelum pajak, layanan, dan pembulatan).
  final double? subtotal;

  /// Pajak (PB1/PPN/Tax) dan namanya pada struk, mis. "PB1".
  final double? taxAmount;
  final String? taxLabel;
  final double? serviceAmount;
  final double? discountAmount;

  /// Pembulatan; negatif bila dibulatkan ke bawah (mis. -98).
  final double? roundingAmount;

  /// Jumlah harga barang yang seharusnya (subtotal, atau total dikurangi
  /// pajak/layanan). Dipakai memeriksa keterbacaan barang.
  final double? itemsTarget;

  /// Jumlah barang menurut baris "4 items" pada struk.
  final int? itemsCount;

  /// Kata yang dikoreksi otomatis (mis. "Nalang" -> "Malang").
  final List<TextCorrection> corrections;

  /// True bila struk memuat rincian yang menjelaskan selisih subtotal dan total.
  bool get hasBreakdown =>
      subtotal != null &&
      (taxAmount != null ||
          serviceAmount != null ||
          discountAmount != null ||
          roundingAmount != null);

  /// Jumlah barang yang diharapkan: subtotal bila ada, selain itu total.
  double? get expectedItemsTotal => itemsTarget ?? totalAmount;

  /// True bila [itemsSum] sama dengan subtotal, subtotal setelah diskon, atau
  /// total struk. [relative] melonggarkan selisih sebagai pecahan dari target.
  bool itemsMatch(
    double itemsSum, {
    double relative = 0,
    double absolute = 1,
  }) {
    final double? target = itemsTarget;
    final double? discount = discountAmount;
    final double? total = totalAmount;
    final List<double> targets = <double>[
      if (target != null) ...<double>[
        target,
        if (discount != null) target - discount,
      ],
      if (total != null) total,
    ];
    return targets.any((double t) {
      final double tolerance =
          t * relative > absolute ? t * relative : absolute;
      return (itemsSum - t).abs() <= tolerance;
    });
  }

  /// Penjelasan rumus total, mis.
  /// "Subtotal Rp37.362 + PB1 Rp3.736 − Pembulatan Rp98 = Rp41.000".
  String? breakdownText(String Function(double) money) {
    final double? sub = subtotal;
    final double? total = totalAmount;
    if (!hasBreakdown || sub == null || total == null) return null;
    final StringBuffer text = StringBuffer('Subtotal ${money(sub)}');
    void add(String label, double? value, {bool minus = false}) {
      if (value == null || value.abs() < 1) return;
      final bool negative = minus ? value > 0 : value < 0;
      text.write(' ${negative ? '−' : '+'} $label ${money(value.abs())}');
    }

    add('Layanan', serviceAmount);
    add(taxLabel ?? 'Pajak', taxAmount);
    add('Diskon', discountAmount, minus: true);
    add('Pembulatan', roundingAmount);
    text.write(' = ${money(total)}');
    return text.toString();
  }

  /// Nama cabang dan alamat toko dari kepala struk (kosong bila tidak ada).
  final StoreAddress address;

  /// True bila total diambil dari baris berkata kunci (TOTAL, JUMLAH, dll.),
  /// bukan tebakan dari nominal terbesar.
  final bool totalFromKeyword;

  final String? merchantName;
  final DateTime? transactionDate;
  final double? totalAmount;

  /// Barang yang dikenali dari baris-baris struk (nama, jumlah, harga).
  final List<ParsedItem> items;

  /// `ParsingStatus.success`, `partial`, atau `failed`.
  final String status;

  /// Nama barang saja (kompatibilitas).
  List<String> get itemNames =>
      items.map((ParsedItem item) => item.name).toList();

  /// Jumlah harga seluruh barang.
  double get itemsTotal => items.fold<double>(
        0,
        (double sum, ParsedItem item) => sum + item.totalPrice,
      );

  /// Teks gabungan merchant + nama barang (untuk catatan klasifikasi tingkat struk).
  String get classificationText {
    final String merchant = (merchantName ?? '').trim();
    return <String>[if (merchant.isNotEmpty) merchant, ...itemNames].join(' ');
  }
}

/// Hasil menganalisis judul toko.
class _MerchantInfo {
  const _MerchantInfo(
    this.index, {
    this.brand,
    this.branch,
    this.street,
    this.city,
  });

  final int index;
  final String? brand;
  final String? branch;
  final String? street;
  final String? city;
}

/// Angka-angka ringkasan pada bagian bawah struk.
class _Summary {
  double? subtotal;
  double? tax;
  String? taxLabel;
  double? service;
  double? discount;
  double? rounding;
  double? total;
  double? grand;
  String grandRaw = '';

  /// Jumlah yang dibayar setelah semua angka diperiksa silang; null bila
  /// tidak ada ringkasan yang bisa dipercaya.
  double? payable;

  /// Jumlah harga barang yang seharusnya (sebelum pajak/layanan/pembulatan).
  double? itemsTarget;

  static bool _isSubsequence(String small, String big) {
    if (small.isEmpty) return false;
    int at = 0;
    for (int i = 0; i < big.length && at < small.length; i++) {
      if (big[i] == small[at]) at++;
    }
    return at == small.length;
  }

  void resolve(ParsingService parser) {
    final double rounding = this.rounding ?? 0;
    final double tolerance = 1.5;
    final List<double> candidates = <double>[
      if (total != null) total! + rounding,
      if (subtotal != null &&
          (tax != null || service != null || discount != null))
        subtotal! + (tax ?? 0) + (service ?? 0) - (discount ?? 0) + rounding,
    ];

    final double? g = grand;
    if (g != null) {
      final bool plausible = g >= ParsingService._minAmount;
      if (plausible &&
          (candidates.isEmpty ||
              candidates.any((double c) => (c - g).abs() <= tolerance))) {
        payable = g;
      } else {
        // Grand total salah baca ("4.00" padahal 41.000): pulihkan dari hitungan
        // bila angkanya hanya kehilangan beberapa digit.
        final String digits = grandRaw.replaceAll(RegExp(r'\D'), '');
        for (final double c in candidates) {
          if (c >= ParsingService._minAmount &&
              _isSubsequence(digits, c.round().toString())) {
            payable = c;
            break;
          }
        }
        if (payable == null) {
          if (candidates.length >= 2 &&
              (candidates[0] - candidates[1]).abs() <= tolerance) {
            payable = candidates.first;
          } else if (plausible) {
            payable = g;
          } else if (candidates.isNotEmpty &&
              candidates.first >= ParsingService._minAmount) {
            payable = candidates.first;
          }
        }
      }
    } else if (candidates.isNotEmpty &&
        candidates.first >= ParsingService._minAmount) {
      payable = candidates.first;
    }

    double? target = subtotal;
    final double? pay = payable;
    if (target == null &&
        pay != null &&
        (tax != null || service != null || discount != null)) {
      target = pay - rounding - (tax ?? 0) - (service ?? 0) + (discount ?? 0);
    }
    if (target != null && target >= ParsingService._minAmount) {
      itemsTarget = target;
    }
  }
}

/// Satu angka pada ekor baris barang (token asli dan nilainya).
class _Num {
  const _Num(this.token, this.value);

  final String token;
  final double value;
}

/// Baris barang yang dipecah menjadi teks nama dan ekor angka.
class _Tail {
  const _Tail(this.name, this.nums, this.hasMarker, [this.explicit = false]);

  final String name;
  final List<_Num> nums;

  /// True bila ada penanda jumlah (x, X, @, *) ATAU satuan ("2 SAK").
  final bool hasMarker;

  /// True hanya bila ada tanda kali yang tegas (x, X, @, *). Tanpa itu
  /// ("2 SAK 130.000") angka terakhir lebih mungkin subtotal.
  final bool explicit;
}

/// Hasil penafsiran angka: jumlah, harga satuan, total, dan potongan nama.
class _Interp {
  const _Interp(this.qty, this.unit, this.total, this.suffix,
      {this.altUnit, this.altTotal});

  final double qty;
  final double unit;
  final double total;
  final String suffix;

  /// Tafsir alternatif (jumlah sama) bila angka ambigu antara subtotal
  /// dan harga satuan.
  final double? altUnit;
  final double? altTotal;
}

/// Smart Parsing berbasis Regular Expression untuk mengekstrak
/// Nama Merchant, Tanggal, Total Nominal, dan daftar barang.
class ParsingService {
  const ParsingService();

  static const int _merchantSearchLimit = 8;
  static const int _maxItems = 60;
  static const double _maxValue = 1e9;
  static const double _minAmount = 100;

  // ------------------------------------------------------------------ pola
  static final RegExp _merchantSkip = RegExp(
    r'^(?:jl|jln|jalan|telp|tel|telepon|hp|wa|npwp|kasir|cashier|no|nomor|struk|faktur|invoice|tanggal|tgl|date|alamat|www|http|email|kode|order|resi|trx|selamat|welcome|terima|thank|info|table|meja|purpose|pax|server|waiter|guest|customer|pelanggan|bill|check|operator|shift|antrian|queue|dine|take|item|items|free|min|time|waktu)\b',
    caseSensitive: false,
  );

  /// Nama dagang jaringan ritel. Struknya sering diawali nama badan usaha
  /// (mis. "PT INDOMARCO PRISMATAMA"), padahal yang dikenal pengguna adalah
  /// nama tokonya. Pola dibuat longgar agar tetap cocok saat OCR sedikit salah
  /// baca (mis. "PRISMATAMA" terbaca "PFISMATAMA").
  static final List<(RegExp, String)> _knownChains = <(RegExp, String)>[
    (RegExp(r'alfa\s*midi|midi\s*utama', caseSensitive: false), 'Alfamidi'),
    (
      RegExp(r'alfa\s*mart|sumber\s*alfaria|alfaria\s*tri',
          caseSensitive: false),
      'Alfamart',
    ),
    (RegExp(r'indo\s*grosir', caseSensitive: false), 'Indogrosir'),
    (
      RegExp(r'indo\s*mar[ce]t|indo\s*marco|indomar\w*\s*p\w{1,2}smatama',
          caseSensitive: false),
      'Indomaret',
    ),
    (RegExp(r'lawson', caseSensitive: false), 'Lawson'),
    (RegExp(r'family\s*mart', caseSensitive: false), 'FamilyMart'),
    (RegExp(r'circle\s*k\b', caseSensitive: false), 'Circle K'),
    (RegExp(r'super\s*indo', caseSensitive: false), 'Super Indo'),
    (RegExp(r'hypermart|matahari\s*putra', caseSensitive: false), 'Hypermart'),
    (RegExp(r'transmart|trans\s*retail', caseSensitive: false), 'Transmart'),
  ];

  /// Baris alamat pada kepala struk (bukan barang belanjaan).
  static final RegExp _addressLike = RegExp(
    r'\b(?:kec|kecamatan|kel|kelurahan|kab|kabupaten|karupaten|kota|kodya|desa|dusun|jl|jln|jalan|gedung|gd|komplek|komp|perum|perumahan|ruko|blok|provinsi|prov|kode\s*pos|rt|rw)\b\.?',
    caseSensitive: false,
  );

  /// Baris yang diakhiri kode pos 5 digit (mis. "..., KABUPATEN MALANG, 65174").
  static final RegExp _postalCodeEnd = RegExp(r',\s*\d{5}\s*$');

  /// Lima digit di ujung baris tanpa koma (mis. "MALANG 65145"). Hanya dianggap
  /// kode pos bila berada di kepala struk (sebelum baris tanggal), karena harga
  /// tanpa pemisah ribuan (mis. "Americano 25000") juga lima digit.
  static final RegExp _postalCodeLoose = RegExp(r'\s\d{5}\s*$');

  /// Pemandu titik/garis antara nama dan harga ("Kopi Susu.......18.000").
  static final RegExp _leaders = RegExp(r'\.{2,}|_{2,}|-{3,}|…+|·{2,}|=');

  /// Token harga yang memuat huruf mirip angka S/B/Z ("12.S00").
  static final RegExp _priceLookalike =
      RegExp(r'^\d[\dSBZ]*[.,][\dSBZ]{3}(?:[.,][\dSBZ]{3})*$');

  /// Harga yang terpotong spasi setelah pemisah ("12. 000" -> "12.000").
  static final RegExp _splitAfterSeparator =
      RegExp(r'(?<![\d.,])(\d{1,3})([.,]) (\d{3})(?!\d)');

  /// Ribuan yang dipisah spasi oleh OCR ("32 000", "1 250 000").
  static final RegExp _spacedThousands =
      RegExp(r'(?<![\d.,])(\d{1,3})((?: \d{3})+)(?![\d.,])');

  /// Kata satuan jumlah yang menempel pada angka ("2 SAK", "1 KG", "3 PCS").
  static final RegExp _qtyUnitEnd = RegExp(
    r'(?:^|\s)(\d{1,3}(?:[.,]\d{1,2})?)\s+(?:pcs|pc|bh|buah|sak|kg|ltr|lt|btl|botol|bks|bungkus|pak|pack|box|dus|lsn|lusin|unit|porsi|psg|pasang|lbr|lembar|rim|roll|meter|mtr|m)\.?$',
    caseSensitive: false,
  );

  /// Baris potongan harga yang melekat pada barang di atasnya.
  static final RegExp _discountLine = RegExp(
    r'\b(?:disc|diskon|discount|potongan|promo|hemat|voucher)\b',
    caseSensitive: false,
  );

  static final RegExp _longDigits = RegExp(r'\d{6,}');
  static final RegExp _phoneLike = RegExp(r'\d{2,4}[\s\-]\d{5,}');

  static final RegExp _dateKeyword =
      RegExp(r'\b(?:tgl|tanggal|date|waktu|time)\b', caseSensitive: false);
  static final RegExp _dateIso =
      RegExp(r'(?<!\d)(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})(?!\d)');
  static final RegExp _dateDmy =
      RegExp(r'(?<!\d)(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4}|\d{2})(?!\d)');
  static final RegExp _dateMonthName = RegExp(
    r'(?<!\d)(\d{1,2})\s*(jan|feb|mar|apr|mei|may|jun|jul|agu|aug|sep|okt|oct|nov|des|dec)[a-z]*\.?\s*,?\s*(\d{4}|\d{2})(?!\d)',
    caseSensitive: false,
  );
  static const Map<String, int> _months = <String, int>{
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'mei': 5,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'agu': 8,
    'aug': 8,
    'sep': 9,
    'okt': 10,
    'oct': 10,
    'nov': 11,
    'des': 12,
    'dec': 12,
  };

  static final RegExp _totalStrong = RegExp(
    r'grand\s*total|total\s*(?:bayar|belanja|tagihan|pembayaran|akhir|transaksi)|jumlah\s*(?:bayar|tagihan)|amount\s*due|total\s*due|net\s*total',
    caseSensitive: false,
  );
  static final RegExp _totalStrongExclude =
      RegExp(r'sub\s*-?\s*total|kembali|change', caseSensitive: false);
  static final RegExp _totalWeak =
      RegExp(r'\b(?:total|jumlah|tagihan|amount)\b', caseSensitive: false);
  static final RegExp _totalWeakExclude = RegExp(
    r'sub\s*-?\s*total|kembali|change|diskon|discount|hemat',
    caseSensitive: false,
  );
  static final RegExp _fallbackExclude = RegExp(
    r'\b(?:tunai|cash|kembali|kembalian|change|bayar|debit|kredit|card|kartu|qris|ppn|pajak|tax|diskon|discount|npwp|telp|telepon|tel|hp|nomor|no|tgl|tanggal|jam|kasir|cashier|member|poin|point|saldo)\b',
    caseSensitive: false,
  );

  static final RegExp _rpPrefix =
      RegExp(r'(?<![A-Za-z])rp\.?\s*', caseSensitive: false);
  static final RegExp _amountToken = RegExp(
    r'(?<![\d.,])(\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)(?!\d)',
  );

  static final RegExp _totalBoundary = RegExp(
    r'\b(?:sub\s*-?\s*total|total|jumlah)\b',
    caseSensitive: false,
  );
  static final RegExp _itemExclude = RegExp(
    r'\b(?:sub\s*-?\s*total|total|jumlah|tunai|cash|kembali|kembalian|change|ppn|pajak|tax|diskon|discount|disc|potongan|promo|voucher|pembulatan|rounding|bonus|cashback|bayar|kasir|cashier|tanggal|tgl|jam|struk|terima\s*kasih|npwp|member|poin|point|debit|kredit|qris|telp|telepon|alamat|invoice|faktur|harga|hemat|saving|no|nomor|pb\s*-?\s*1|service|svc|vat|gst|tip|items?|info|table|meja|purpose|pax|server|waiter|guest|customer|pelanggan|dine\s*in|take\s*-?\s*away|takeaway|netto)\b|www|http|@',
    caseSensitive: false,
  );

  // Token pada ekor baris barang: angka, penanda kali, "X1", "2x", atau "2x3.500".
  static final RegExp _tokNum = RegExp(r'^[\d.,]*\d[\d.,]*$');
  static final RegExp _tokMark = RegExp(r'^[xX@*×]$');
  static final RegExp _tokMarkN = RegExp(r'^[xX@*×]([\d.,]*\d[\d.,]*)$');
  static final RegExp _tokNMark = RegExp(r'^([\d.,]*\d[\d.,]*)[xX@*×]$');
  static final RegExp _tokNMN =
      RegExp(r'^([\d.,]*\d[\d.,]*)[xX@*×]([\d.,]*\d[\d.,]*)$');
  static final RegExp _digitLookalike = RegExp(r'^[\dOoIl.,]+$');
  static final RegExp _lookalikeLetter = RegExp(r'[OoIl]');
  static final RegExp _leadingQty =
      RegExp(r'^(\d{1,2})\s*[xX]?\s+(?=[A-Za-z])');
  static final RegExp _trailingFlag = RegExp(r'\s+[A-Za-z]$');
  static final RegExp _qtyInName =
      RegExp(r'\d+(?:[.,]\d+)?\s*[xX@*]\s*[\d.,]+');
  static final RegExp _numericWord = RegExp(r'^[\d.,]+$');
  static final RegExp _hasLetter = RegExp(r'[A-Za-z]');

  // --------------------------------------------------------------- publik

  /// Mengurai teks mentah OCR menjadi data transaksi terstruktur.
  ParsedReceiptData parse(String rawText) {
    final List<TextCorrection> corrections = <TextCorrection>[];
    final List<String> lines = _splitLines(rawText, corrections);
    if (lines.isEmpty) {
      return const ParsedReceiptData(status: ParsingStatus.failed);
    }

    final _MerchantInfo info = _analyzeMerchant(lines);
    final int merchantIndex = info.index;
    final String? merchant = _knownChainName(lines) ?? info.brand;
    final DateTime? date = _extractDate(lines);

    // Subtotal, pajak, pembulatan, dan grand total saling diperiksa; angka
    // total yang rusak dipulihkan dari hitungan (mis. "4.00" -> 41.000).
    final _Summary summary = _extractSummary(lines);
    final double? keywordTotal = summary.payable ?? _extractKeywordTotal(lines);
    final double? total = keywordTotal ?? _fallbackTotal(lines);
    final double? itemsTarget = summary.itemsTarget;
    final int? itemsCount = _extractItemsCount(lines);

    List<ParsedItem> items =
        _extractItems(lines, startIndex: merchantIndex + 1);
    if (items.isEmpty && keywordTotal != null && keywordTotal >= _minAmount) {
      final ParsedItem? only =
          _singleItemFallback(lines, merchantIndex + 1, keywordTotal) ??
              _singleItemFallback(lines, 0, keywordTotal);
      if (only != null) items = <ParsedItem>[only];
    }

    // Angka yang ambigu (subtotal atau harga satuan?) ditentukan oleh jumlah
    // barang pada struk: subtotal bila ada, selain itu total. Harus sebelum
    // penyaringan di bawah, karena tafsir "harga satuan" yang salah membuat
    // total sebuah barang melampaui total belanja.
    items = reconcileWithTotal(items, itemsTarget ?? keywordTotal);

    // Jumlah barang yang hilang dipulihkan dari baris "4 items".
    items = _inferQuantities(items, itemsCount);

    // Satu barang tidak mungkin lebih mahal dari total belanja. Baris seperti
    // itu hampir pasti salah baca (kode pos, nomor telepon, nomor transaksi).
    if (keywordTotal != null && keywordTotal > 0) {
      items = items
          .where((ParsedItem item) => item.totalPrice <= keywordTotal * 1.01)
          .toList();
    }

    // Huruf yang hilang pada nama barang dilengkapi dari kosakata barang.
    items = _correctItemNames(items, corrections);

    final int found = <Object?>[
      if (merchant != null && merchant.isNotEmpty) merchant,
      date,
      total,
    ].whereType<Object>().length;

    final String status = found == 3
        ? ParsingStatus.success
        : (found == 0 ? ParsingStatus.failed : ParsingStatus.partial);

    // Alamat dibaca dari teks yang sudah dikoreksi; bila struk tidak memuat
    // baris alamat, cabang dan kota pada judul toko dipakai.
    final StoreAddress address = const StoreAddressExtractor()
        .extract(lines.join('\n'), merchantName: merchant)
        .merged(
          branchName: info.branch,
          street: info.street,
          city: info.city,
        );

    return ParsedReceiptData(
      merchantName: (merchant == null || merchant.isEmpty) ? null : merchant,
      transactionDate: date,
      totalAmount: total,
      items: items,
      status: status,
      totalFromKeyword: keywordTotal != null,
      address: address,
      subtotal: summary.subtotal,
      taxAmount: summary.tax,
      taxLabel: summary.taxLabel,
      serviceAmount: summary.service,
      discountAmount: summary.discount,
      roundingAmount: summary.rounding,
      itemsTarget: itemsTarget,
      itemsCount: itemsCount,
      corrections: corrections,
    );
  }

  List<ParsedItem> _correctItemNames(
    List<ParsedItem> items,
    List<TextCorrection> corrections,
  ) {
    const OcrTextCorrector corrector = OcrTextCorrector();
    return <ParsedItem>[
      for (final ParsedItem item in items)
        () {
          final String fixed =
              corrector.correctItemName(item.name, sink: corrections);
          return fixed == item.name
              ? item
              : ParsedItem(
                  name: fixed,
                  quantity: item.quantity,
                  unitPrice: item.unitPrice,
                  totalPrice: item.totalPrice,
                  alternative: item.alternative,
                  quantityKnown: item.quantityKnown,
                );
        }(),
    ];
  }

  // ------------------------------------------------------ ringkasan angka

  static final RegExp _subtotalKey =
      RegExp(r'sub\s*-?\s*tot', caseSensitive: false);
  static final RegExp _taxKey = RegExp(
      r'\b(?:pb\s*-?\s*1|ppn|pajak(?:\s*restoran)?|tax|vat|gst)\b',
      caseSensitive: false);
  static final RegExp _serviceKey = RegExp(
      r'\b(?:service(?:\s*charge)?|svc|biaya\s*layanan)\b',
      caseSensitive: false);
  static final RegExp _discountKey = RegExp(
      r'\b(?:diskon|discount|disc|potongan|voucher|promo)\b',
      caseSensitive: false);
  static final RegExp _roundingKey =
      RegExp(r'\b(?:rounding|pembulatan|pembulat)\b', caseSensitive: false);
  static final RegExp _grandKey = RegExp(
      r'grand\s*total|total\s*(?:bayar|belanja|tagihan|pembayaran|akhir|transaksi)|jumlah\s*(?:bayar|tagihan)|amount\s*due|total\s*due|net\s*total|balance\s*due',
      caseSensitive: false);
  static final RegExp _plainTotalKey =
      RegExp(r'\btotal\b', caseSensitive: false);
  static final RegExp _inclusiveKey = RegExp(
      r'\b(?:include|included|incl|inc|termasuk|dpp)\b',
      caseSensitive: false);
  static final RegExp _totalNoise = RegExp(
      r'\b(?:item|items|qty|pcs|barang|produk|pax)\b',
      caseSensitive: false);

  /// Angka terakhir pada baris ringkasan; "10%" bukan nominal. Mengembalikan
  /// nilai (negatif bila diawali "-") dan teks aslinya.
  static final RegExp _summaryNumber = RegExp(
    r'(?<![\d.,])(-?)\s?(\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)(?!\d)(?!\s*%)',
  );

  ({double value, String raw})? _numberOnLine(String line) {
    final List<RegExpMatch> all = _summaryNumber.allMatches(line).toList();
    if (all.isEmpty) return null;
    final RegExpMatch m = all.last;
    final String raw = m.group(2) ?? '';
    final double? value = _parseAmount(raw);
    if (value == null) return null;
    return (value: (m.group(1) ?? '').isEmpty ? value : -value, raw: raw);
  }

  _Summary _extractSummary(List<String> lines) {
    final _Summary s = _Summary();
    bool inSummary = false;
    for (final String line in lines) {
      if (_inclusiveKey.hasMatch(line)) continue; // Keterangan, bukan tambahan.
      final ({double value, String raw})? n = _numberOnLine(line);
      if (n == null) continue;

      if (_subtotalKey.hasMatch(line)) {
        inSummary = true;
        if (n.value >= _minAmount) s.subtotal ??= n.value;
      } else if (_grandKey.hasMatch(line)) {
        inSummary = true;
        s.grand = n.value;
        s.grandRaw = n.raw;
      } else if (_plainTotalKey.hasMatch(line) && !_totalNoise.hasMatch(line)) {
        inSummary = true;
        if (n.value >= _minAmount) s.total = n.value;
      } else if (inSummary && _roundingKey.hasMatch(line)) {
        s.rounding = n.value;
      } else if (inSummary && _taxKey.hasMatch(line)) {
        s.tax = (s.tax ?? 0) + n.value.abs();
        s.taxLabel ??= _taxLabel(line);
      } else if (inSummary && _serviceKey.hasMatch(line)) {
        s.service = (s.service ?? 0) + n.value.abs();
      } else if (inSummary && _discountKey.hasMatch(line)) {
        s.discount = (s.discount ?? 0) + n.value.abs();
      }
    }
    s.resolve(this);
    return s;
  }

  String _taxLabel(String line) {
    final String lower = line.toLowerCase();
    if (RegExp(r'pb\s*-?\s*1').hasMatch(lower)) return 'PB1';
    if (lower.contains('ppn')) return 'PPN';
    if (lower.contains('vat')) return 'VAT';
    if (lower.contains('gst')) return 'GST';
    if (lower.contains('tax')) return 'Tax';
    return 'Pajak';
  }

  /// "4 items" -> 4: jumlah seluruh barang pada struk.
  static final RegExp _itemsCountLine = RegExp(
    r'^\W*(\d{1,3})\s*(?:items?|pcs|barang|produk|qty)\W*$',
    caseSensitive: false,
  );

  int? _extractItemsCount(List<String> lines) {
    for (final String line in lines) {
      final RegExpMatch? m = _itemsCountLine.firstMatch(line);
      if (m != null) return int.tryParse(m.group(1) ?? '');
    }
    return null;
  }

  /// Memulihkan jumlah barang yang tidak tercantum (mis. angka di depan nama
  /// terpotong OCR) dari jumlah seluruh barang pada baris "N items".
  List<ParsedItem> _inferQuantities(List<ParsedItem> items, int? count) {
    if (count == null || items.isEmpty) return items;
    final List<int> unknown = <int>[
      for (int i = 0; i < items.length; i++)
        if (!items[i].quantityKnown) i,
    ];
    if (unknown.isEmpty) return items;

    final double known = items
        .where((ParsedItem i) => i.quantityKnown)
        .fold<double>(0, (double s, ParsedItem i) => s + i.quantity);
    final double remaining = count - known;
    // Hanya bila tepat satu barang yang jumlahnya tidak diketahui; bila lebih
    // dari satu, pembagiannya tidak dapat ditentukan.
    if (unknown.length != 1 ||
        remaining < 1 ||
        remaining != remaining.roundToDouble()) {
      return items;
    }
    final List<ParsedItem> result = List<ParsedItem>.of(items);
    result[unknown.single] = items[unknown.single].withQuantity(remaining);
    return result;
  }

  // ------------------------------------------------------ judul toko

  /// Memilih baris nama toko dan memisahkan merek, cabang, serta kota.
  /// Contoh: "Wizzmie Muharto Malang" -> merek Wizzmie, cabang Muharto,
  /// kota Malang. Logo yang terbaca rusak ("W/ZZmne") lalu diulang lengkap
  /// pada baris berikutnya, memakai baris yang lengkap.
  _MerchantInfo _analyzeMerchant(List<String> lines) {
    final int limit = lines.length < _merchantSearchLimit
        ? lines.length
        : _merchantSearchLimit;
    final List<int> candidates = <int>[
      for (int i = 0; i < limit; i++)
        if (_isMerchantCandidate(lines[i])) i,
    ];
    if (candidates.isEmpty) return const _MerchantInfo(-1);

    int index = candidates.first;
    if (candidates.length > 1) {
      final int next = candidates[1];
      if (next - index <= 2 && _logoEchoes(lines[index], lines[next])) {
        index = next;
      }
    }

    final String cleaned = _cleanMerchant(lines[index]);
    final List<String> words =
        cleaned.split(' ').where((String w) => w.isNotEmpty).toList();

    // Kota di akhir judul membuktikan bahwa kata sebelumnya adalah cabang.
    String? city;
    int cityStart = -1;
    for (int k = words.length - 1; k >= 1; k--) {
      final ({String name, int length})? hit =
          IndonesianPlaces.cityAt(words, k);
      if (hit != null && k + hit.length == words.length) {
        city = hit.name;
        cityStart = k;
        break;
      }
    }
    if (city == null) return _MerchantInfo(index, brand: cleaned);

    final List<String> rest = words.sublist(0, cityStart);
    String? branch;
    String? street;
    List<String> brandWords = rest;
    if (rest.length >= 2 && IndonesianPlaces.isStreet(rest.last)) {
      branch = rest.last;
      street = 'Jalan ${rest.last}';
      brandWords = rest.sublist(0, rest.length - 1);
    }
    return _MerchantInfo(
      index,
      brand: brandWords.join(' '),
      branch: branch,
      street: street,
      city: city,
    );
  }

  /// True bila [logo] adalah bacaan rusak dari kata pertama [full], dan
  /// [full] lebih lengkap (lebih banyak kata).
  bool _logoEchoes(String logo, String full) {
    String letters(String t) =>
        t.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    final String a = letters(logo);
    final List<String> fullWords =
        full.split(' ').where((String w) => w.isNotEmpty).toList();
    if (a.length < 3 || fullWords.isEmpty) return false;
    final String b = letters(fullWords.first);
    if (b.length < 3) return false;
    final int longest = a.length > b.length ? a.length : b.length;
    final double similarity = 1 - OcrTextCorrector.distance(a, b) / longest;
    final int logoWords =
        logo.split(' ').where((String w) => w.isNotEmpty).length;
    return similarity >= 0.55 && fullWords.length > logoWords;
  }

  // ------------------------------------------------- cocokkan dengan total

  /// Toleransi selisih (rupiah) saat mencocokkan jumlah barang dengan total.
  static double _matchTolerance(double total) => 1 + total * 0.0005;

  /// Menentukan tafsir baris ambigu memakai total struk.
  ///
  /// Bila jumlah harga barang sudah sama dengan total, tafsir utama dipakai.
  /// Bila tidak, dicari kombinasi baris yang ditafsirkan ulang (subtotal <->
  /// harga satuan) sehingga jumlahnya PERSIS sama dengan total; kombinasi
  /// dengan perubahan paling sedikit menang. Tanpa kombinasi yang cocok
  /// (mis. ada pajak atau diskon global), hasil utama dibiarkan.
  List<ParsedItem> reconcileWithTotal(List<ParsedItem> items, double? total) {
    if (total == null || total <= 0) return items;
    final List<int> ambiguous = <int>[
      for (int i = 0; i < items.length; i++)
        if (items[i].isAmbiguous) i,
    ];
    if (ambiguous.isEmpty) return items;

    final double tolerance = _matchTolerance(total);
    final double current =
        items.fold<double>(0, (double s, ParsedItem i) => s + i.totalPrice);
    if ((current - total).abs() <= tolerance) return items;

    final List<double> deltas = <double>[
      for (final int i in ambiguous)
        items[i].alternative!.totalPrice - items[i].totalPrice,
    ];

    int? best;
    int bestFlips = 1 << 30;
    final int n = ambiguous.length;
    if (n <= 14) {
      for (int mask = 1; mask < (1 << n); mask++) {
        double sum = current;
        int flips = 0;
        for (int b = 0; b < n; b++) {
          if (mask & (1 << b) != 0) {
            sum += deltas[b];
            flips++;
          }
        }
        if ((sum - total).abs() <= tolerance && flips < bestFlips) {
          best = mask;
          bestFlips = flips;
        }
      }
    } else {
      // Terlalu banyak baris ambigu: coba semua sekaligus dan satu per satu.
      final int all = (1 << n) - 1;
      final double allSum = current + deltas.fold<double>(0, (a, b) => a + b);
      if ((allSum - total).abs() <= tolerance) best = all;
    }
    if (best == null) return items;

    final List<ParsedItem> resolved = List<ParsedItem>.of(items);
    for (int b = 0; b < n; b++) {
      if (best & (1 << b) != 0) {
        final int index = ambiguous[b];
        resolved[index] = items[index].alternative!;
      }
    }
    return resolved;
  }

  /// Memotong harga sebuah barang (baris DISC di bawahnya), tafsir
  /// alternatifnya ikut dipotong.
  ParsedItem _applyCut(ParsedItem item, double cut) {
    final double total = item.totalPrice - cut;
    if (total < _minAmount) return item;
    final ParsedItem? alt = item.alternative;
    return ParsedItem(
      name: item.name,
      quantity: item.quantity,
      unitPrice: total / item.quantity,
      totalPrice: total,
      alternative: alt == null ? null : _applyCut(alt, cut),
    );
  }

  // ------------------------------------------------------------- util umum

  /// Baris yang memuat harga (barang atau ringkasan), bukan judul/alamat.
  static final RegExp _priceToken =
      RegExp(r'\d{1,3}(?:[.,]\d{3})+|\s\d{4,}\s*$');
  static final RegExp _levelWord = RegExp(
      r'^(?:lv|lvl|level|lev|size|ukuran|tipe|type|paket|menu|set|gen|no)\.?$',
      caseSensitive: false);
  static final RegExp _smallInt = RegExp(r'^\d{1,2}$');

  List<String> _splitLines(String rawText, List<TextCorrection> corrections) {
    const OcrTextCorrector corrector = OcrTextCorrector();
    return rawText
        .split(RegExp(r'\r?\n'))
        .map((String l) {
          final String cleaned = _joinSpacedThousands(_fixDigitLookalikes(l
              .replaceAll(_leaders, ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim()));
          // Perbaiki kata kunci/kota/jalan yang hurufnya hilang atau tertukar,
          // dan "Ly 1" (kerusakan dari "Lv 1") sebelum dicocokkan ke pola.
          return corrector
              .correctLine(cleaned,
                  sink: corrections, lenient: !_priceToken.hasMatch(cleaned))
              .replaceAllMapped(
                  _levelGarble, (Match m) => '${m.group(1)} Lv ${m.group(2)}');
        })
        .where((String l) => l.isNotEmpty)
        .toList();
  }

  /// "Mie Disko Ly 1" -> "Mie Disko Lv 1": tingkat pedas/ukuran yang terbaca
  /// "Ly"/"Lu"/"Lw" setelah sebuah kata dan sebelum angka kecil.
  static final RegExp _levelGarble =
      RegExp(r'([A-Za-z]) (?:Ly|Lu|Lw|LV|lv)\.? ?(\d{1,2})(?=\s|$)');

  /// "Minyak Goreng 32 000" -> "Minyak Goreng 32000".
  String _joinSpacedThousands(String line) {
    line = line.replaceAllMapped(
      _splitAfterSeparator,
      (Match m) => '${m.group(1)}${m.group(2)}${m.group(3)}',
    );
    return line.replaceAllMapped(
      _spacedThousands,
      (Match m) => '${m.group(1)}${(m.group(2) ?? '').replaceAll(' ', '')}',
    );
  }

  /// OCR sering salah membaca angka 0 sebagai huruf "o" dan angka 1 sebagai "l"/"I"
  /// (mis. "500.00o", "2.OOO", "Xl"). Pada token yang jelas berupa angka,
  /// huruf yang mirip angka dikembalikan.
  String _fixDigitLookalikes(String line) {
    final String fixed = line.split(' ').map((String token) {
      final int digits = RegExp(r'\d').allMatches(token).length;
      final bool hasSeparator = token.contains('.') || token.contains(',');
      if (token.length >= 3 &&
          _digitLookalike.hasMatch(token) &&
          _lookalikeLetter.hasMatch(token) &&
          (digits >= 2 || (digits >= 1 && hasSeparator))) {
        return token
            .replaceAll(RegExp(r'[Oo]'), '0')
            .replaceAll(RegExp(r'[Il]'), '1');
      }
      // S/B/Z hanya dipulihkan pada angka berpemisah yang jelas berupa harga
      // ("12.S00" -> "12.500", "1B.000" -> "18.000"), agar kata tidak rusak.
      if (hasSeparator &&
          digits >= 2 &&
          _priceLookalike.hasMatch(token) &&
          RegExp(r'[SBZ]').hasMatch(token)) {
        return token
            .replaceAll('S', '5')
            .replaceAll('B', '8')
            .replaceAll('Z', '2');
      }
      return token;
    }).join(' ');
    // Penanda jumlah "Xl" / "XI" setelah sebuah angka dibaca sebagai "X1".
    return fixed.replaceAllMapped(
      RegExp(r'(?<=\d) ([xX])([lI])(?=\s|$)'),
      (Match m) => ' ${m.group(1)}1',
    );
  }

  // -------------------------------------------------------------- merchant

  /// Nama toko jaringan ritel yang dikenali di bagian atas struk; null bila tidak ada.
  String? _knownChainName(List<String> lines) {
    final int limit = lines.length < _merchantSearchLimit
        ? lines.length
        : _merchantSearchLimit;
    final String head = lines.sublist(0, limit).join(' ');
    for (final (RegExp pattern, String name) in _knownChains) {
      if (pattern.hasMatch(head)) return name;
    }
    return null;
  }

  bool _isMerchantCandidate(String line) {
    if (line.length > 45) return false;
    if (_merchantSkip.hasMatch(line)) return false;
    if (_longDigits.hasMatch(line) || _phoneLike.hasMatch(line)) return false;
    if (line.contains('@') || line.toLowerCase().contains('.com')) return false;
    if (_dateFromLine(line) != null) return false;

    final int letters = RegExp(r'[A-Za-z]').allMatches(line).length;
    final int visible = line.replaceAll(' ', '').length;
    if (letters < 3 || visible == 0) return false;
    return letters / visible >= 0.6;
  }

  String _cleanMerchant(String line) {
    String name = line
        .replaceAll(RegExp(r'^[^A-Za-z0-9]+'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final int letterCount = RegExp(r'[A-Za-z]').allMatches(name).length;
    final int upperCount = RegExp(r'[A-Z]').allMatches(name).length;
    final bool mostlyUpper = letterCount > 0 && upperCount / letterCount >= 0.8;
    if (name.isNotEmpty && mostlyUpper) {
      name = name
          .split(' ')
          .map(
            (String w) => w.isEmpty
                ? w
                : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
          )
          .join(' ');
    }
    return name;
  }

  // --------------------------------------------------------------- tanggal

  DateTime? _extractDate(List<String> lines) {
    for (final String line in lines) {
      if (!_dateKeyword.hasMatch(line)) continue;
      final DateTime? date = _dateFromLine(line);
      if (date != null) return date;
    }
    for (final String line in lines) {
      final DateTime? date = _dateFromLine(line);
      if (date != null) return date;
    }
    return null;
  }

  DateTime? _dateFromLine(String line) {
    for (final RegExpMatch m in _dateIso.allMatches(line)) {
      final DateTime? date =
          _buildDate(_group(m, 1), _group(m, 2), _group(m, 3));
      if (date != null) return date;
    }
    for (final RegExpMatch m in _dateDmy.allMatches(line)) {
      final DateTime? date =
          _buildDayFirst(_group(m, 1), _group(m, 2), _group(m, 3));
      if (date != null) return date;
    }
    for (final RegExpMatch m in _dateMonthName.allMatches(line)) {
      final String key = (m.group(2) ?? '').toLowerCase();
      final int? month = _months[key];
      final DateTime? date = _buildDate(_group(m, 3), month, _group(m, 1));
      if (date != null) return date;
    }
    return null;
  }

  int? _group(RegExpMatch match, int index) =>
      int.tryParse(match.group(index) ?? '');

  /// Format hari-bulan-tahun; jika bulan > 12 dan hari <= 12, keduanya ditukar.
  DateTime? _buildDayFirst(int? first, int? second, int? year) {
    if (first == null || second == null) return null;
    int day = first;
    int month = second;
    if (month > 12 && day <= 12) {
      final int tmp = day;
      day = month;
      month = tmp;
    }
    return _buildDate(year, month, day);
  }

  DateTime? _buildDate(int? year, int? month, int? day) {
    if (year == null || month == null || day == null) return null;
    int y = year;
    if (y < 100) y += 2000;
    if (y < 2000 || y > DateTime.now().year + 1) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final DateTime date = DateTime(y, month, day);
    if (date.month != month || date.day != day) return null;
    return date;
  }

  // ----------------------------------------------------------------- total

  /// Total dari baris berkata kunci saja; null bila tidak ada.
  double? _extractKeywordTotal(List<String> lines) {
    final double? strong =
        _findAmountByPattern(lines, _totalStrong, _totalStrongExclude);
    if (strong != null) return strong;

    final double? weak =
        _findAmountByPattern(lines, _totalWeak, _totalWeakExclude);
    return weak;
  }

  /// Menelusuri dari baris paling bawah (total biasanya di bagian akhir struk).
  double? _findAmountByPattern(
    List<String> lines,
    RegExp include,
    RegExp exclude,
  ) {
    for (int i = lines.length - 1; i >= 0; i--) {
      final String line = lines[i];
      if (!include.hasMatch(line) || exclude.hasMatch(line)) continue;

      final double? amount = _lastAmountInLine(line);
      if (amount != null) return amount;

      // Nominal kadang terpisah ke baris berikutnya.
      if (i + 1 < lines.length && _isAmountOnlyLine(lines[i + 1])) {
        final double? next = _lastAmountInLine(lines[i + 1]);
        if (next != null) return next;
      }
    }
    return null;
  }

  /// Cadangan bila tidak ada kata kunci total: nominal terbesar pada baris yang layak.
  /// Hasilnya perkiraan; pengguna tetap memvalidasinya di form pratinjau.
  double? _fallbackTotal(List<String> lines) {
    double? best;
    for (final String line in lines) {
      if (_fallbackExclude.hasMatch(line)) continue;
      if (RegExp(r'\d{8,}').hasMatch(line)) continue;
      if (_dateFromLine(line) != null) continue;
      final double? amount = _lastAmountInLine(line);
      if (amount == null) continue;
      if (best == null || amount > best) best = amount;
    }
    return best;
  }

  bool _isAmountOnlyLine(String line) {
    final String cleaned = line.replaceAll(_rpPrefix, ' ');
    return !_hasLetter.hasMatch(cleaned) && _amountToken.hasMatch(cleaned);
  }

  /// Nominal terakhir pada baris (bernilai minimal [_minAmount]).
  double? _lastAmountInLine(String line) {
    final String cleaned = line.replaceAll(_rpPrefix, ' ');
    final List<RegExpMatch> matches = _amountToken.allMatches(cleaned).toList();
    for (int i = matches.length - 1; i >= 0; i--) {
      final double? value = _parseAmount(matches[i].group(1) ?? '');
      if (value != null && value >= _minAmount) return value;
    }
    return null;
  }

  /// Mengonversi teks angka berformat Indonesia/Inggris menjadi double.
  /// Contoh: "17.000" -> 17000, "1.234,50" -> 1234.5, "1,234.50" -> 1234.5.
  double? _parseAmount(String token) {
    if (token.isEmpty) return null;
    final bool hasDot = token.contains('.');
    final bool hasComma = token.contains(',');
    String normalized;

    if (hasDot && hasComma) {
      final String decimalSep =
          token.lastIndexOf('.') > token.lastIndexOf(',') ? '.' : ',';
      final String thousandSep = decimalSep == '.' ? ',' : '.';
      normalized =
          token.replaceAll(thousandSep, '').replaceAll(decimalSep, '.');
    } else if (hasDot || hasComma) {
      final String sep = hasDot ? '.' : ',';
      final List<String> parts = token.split(sep);
      if (parts.length > 2 || parts.last.length == 3) {
        normalized = parts.join();
      } else {
        normalized = '${parts.first}.${parts.last}';
      }
    } else {
      normalized = token;
    }
    return double.tryParse(normalized);
  }

  // ---------------------------------------------------------------- barang

  /// True bila baris menandai akhir daftar barang (TOTAL/SUBTOTAL berisi
  /// nominal). Kepala tabel seperti "Item Qty Harga Jumlah" tidak dihitung.
  bool _isTotalBoundary(List<String> lines, int i) {
    if (!_totalBoundary.hasMatch(lines[i])) return false;
    if (_lastAmountInLine(lines[i]) != null) return true;
    return i + 1 < lines.length && _isAmountOnlyLine(lines[i + 1]);
  }

  List<ParsedItem> _extractItems(List<String> lines,
      {required int startIndex}) {
    int endIndex = lines.length;
    for (int i = startIndex; i < lines.length; i++) {
      if (_isTotalBoundary(lines, i)) {
        endIndex = i;
        break;
      }
    }

    // Kepala struk berakhir di baris tanggal pertama (bila ada).
    int headerEnd = startIndex;
    for (int i = startIndex; i < endIndex; i++) {
      if (_dateFromLine(lines[i]) != null) {
        headerEnd = i;
        break;
      }
    }

    final List<ParsedItem> items = <ParsedItem>[];

    // Nama tanpa harga dan baris harga tanpa nama yang menunggu dipasangkan.
    // Struk berkolom sering terbaca sebagai beberapa nama dulu, lalu harganya.
    final List<String> names = <String>[];
    final List<_Tail> prices = <_Tail>[];

    void flush() {
      if (prices.isNotEmpty && names.isNotEmpty) {
        final int count =
            names.length < prices.length ? names.length : prices.length;
        // Nama terakhir paling dekat dengan harganya; nama yang lebih awal
        // (mis. baris cabang toko) diabaikan bila jumlahnya berlebih.
        final List<String> usedNames = names.sublist(names.length - count);
        for (int k = 0; k < count; k++) {
          final ParsedItem? item = _buildItem(usedNames[k], prices[k].nums,
              prices[k].hasMarker, prices[k].explicit);
          if (item != null) items.add(item);
        }
      }
      names.clear();
      prices.clear();
    }

    for (int i = startIndex; i < endIndex; i++) {
      final String line = lines[i];

      // Potongan harga: kurangi dari barang tepat di atasnya.
      if (_discountLine.hasMatch(line) && !_totalBoundary.hasMatch(line)) {
        flush();
        final double? cut = _lastAmountInLine(line);
        if (cut != null && items.isNotEmpty) {
          items.add(_applyCut(items.removeLast(), cut));
        }
        continue;
      }

      if (_itemExclude.hasMatch(line) ||
          _addressLike.hasMatch(line) ||
          _postalCodeEnd.hasMatch(line) ||
          (i < headerEnd && _postalCodeLoose.hasMatch(line)) ||
          _dateFromLine(line) != null) {
        flush();
        continue;
      }

      final _Tail tail = _splitTail(line);
      final bool named = _letters(tail.name) >= 3;

      if (tail.nums.isEmpty) {
        // Baris berisi nama saja: harganya ada di baris berikutnya.
        if (named) {
          if (prices.isNotEmpty) flush();
          names.add(tail.name);
        } else if (tail.name.trim().isNotEmpty) {
          flush();
        }
        continue;
      }

      if (named) {
        flush();
        final ParsedItem? item =
            _buildItem(tail.name, tail.nums, tail.hasMarker, tail.explicit);
        if (item != null) items.add(item);
      } else {
        prices.add(tail);
      }
      if (items.length >= _maxItems) break;
    }
    flush();
    return items.length > _maxItems ? items.sublist(0, _maxItems) : items;
  }

  /// Cadangan bila tidak ada satu pun baris barang yang dikenali (mis. struk
  /// SPBU atau struk jasa): nama produk pertama dipasangkan dengan total.
  ParsedItem? _singleItemFallback(
      List<String> lines, int startIndex, double total) {
    for (int i = startIndex; i < lines.length; i++) {
      final String line = lines[i];
      if (_isTotalBoundary(lines, i)) break;
      if (_itemExclude.hasMatch(line) ||
          _addressLike.hasMatch(line) ||
          _discountLine.hasMatch(line) ||
          _dateFromLine(line) != null ||
          RegExp(r'\d').hasMatch(line) ||
          line.length > 40) {
        continue;
      }
      final String? name = _cleanItemName(line);
      if (name != null) {
        return ParsedItem(
            name: name, quantity: 1, unitPrice: total, totalPrice: total);
      }
    }
    return null;
  }

  String _normalizeLine(String raw) {
    return raw
        .replaceAll(_rpPrefix, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isTailToken(String t) {
    return _tokNum.hasMatch(t) ||
        _tokMark.hasMatch(t) ||
        _tokMarkN.hasMatch(t) ||
        _tokNMark.hasMatch(t) ||
        _tokNMN.hasMatch(t);
  }

  /// Memisahkan baris menjadi nama (teks di depan) dan ekor angka (di belakang).
  /// Contoh: "AQUA 600ML 3.500" -> nama "AQUA 600ML", angka [3.500];
  /// "PPG 500.000 X1 500.000" -> nama "PPG", angka [500.000, 1, 500.000] (ada penanda x).
  _Tail _splitTail(String rawLine) {
    String line = _normalizeLine(rawLine);
    final String stripped = line.replaceFirst(_trailingFlag, '');
    if (RegExp(r'[\d.,]$').hasMatch(stripped)) line = stripped;

    final List<String> tokens = line.split(' ');
    int i = tokens.length;
    while (i > 0 && _isTailToken(tokens[i - 1])) {
      i--;
    }
    // "Lv 1", "Level 2", "No 5": angka tepat setelah kata itu bagian dari nama
    // barang (tingkat pedas, ukuran, nomor menu), bukan jumlah atau harga.
    if (i > 0 &&
        i < tokens.length &&
        _levelWord.hasMatch(tokens[i - 1]) &&
        _smallInt.hasMatch(tokens[i])) {
      i++;
    }
    List<String> prefix = tokens.sublist(0, i);
    final List<String> tail = tokens.sublist(i);

    // "2 SAK" / "1 KG" sebelum angka harga: angkanya adalah jumlah.
    String? unitQty;
    final RegExpMatch? unit = _qtyUnitEnd.firstMatch(prefix.join(' '));
    if (unit != null && tail.isNotEmpty) {
      unitQty = unit.group(1);
      prefix = prefix.join(' ').substring(0, unit.start).trim().split(' ')
        ..removeWhere((String t) => t.isEmpty);
    }

    final bool hasNumber = tail.any(
      (String t) =>
          _tokNum.hasMatch(t) ||
          _tokMarkN.hasMatch(t) ||
          _tokNMark.hasMatch(t) ||
          _tokNMN.hasMatch(t),
    );
    if (!hasNumber) return _Tail(tokens.join(' '), const <_Num>[], false);

    final List<_Num> nums = <_Num>[];
    bool hasMarker = unitQty != null;
    bool explicit = false;

    void add(String token) {
      final double? value = _parseAmount(token);
      if (value != null && value <= _maxValue) nums.add(_Num(token, value));
    }

    for (final String t in tail) {
      if (_tokMark.hasMatch(t)) {
        hasMarker = true;
        explicit = true;
        continue;
      }
      final RegExpMatch? markN = _tokMarkN.firstMatch(t);
      if (markN != null) {
        hasMarker = true;
        explicit = true;
        add(markN.group(1) ?? '');
        continue;
      }
      final RegExpMatch? nMark = _tokNMark.firstMatch(t);
      if (nMark != null) {
        hasMarker = true;
        explicit = true;
        add(nMark.group(1) ?? '');
        continue;
      }
      final RegExpMatch? nmn = _tokNMN.firstMatch(t);
      if (nmn != null) {
        hasMarker = true;
        explicit = true;
        add(nmn.group(1) ?? '');
        add(nmn.group(2) ?? '');
        continue;
      }
      add(t);
    }
    if (unitQty != null) {
      final double? q = _parseAmount(unitQty);
      if (q != null && q > 0) nums.insert(0, _Num(unitQty, q));
    }
    return _Tail(prefix.join(' '), nums, hasMarker, explicit);
  }

  bool _hasSeparator(String token) =>
      token.contains('.') || token.contains(',');

  /// Menentukan jumlah dan harga satuan dari dua angka di sekitar tanda "x".
  /// Jumlah biasanya lebih kecil dari harga satuan, sehingga "2 x 3.500" dan
  /// "3.500 x2" sama-sama dibaca sebagai 2 buah @ Rp3.500.
  ({double qty, double unit}) _resolveQtyUnit(
      double a, double b, double? total) {
    final bool aIsQty = a <= b;
    final double qty = aIsQty ? a : b;
    double unit = aIsQty ? b : a;
    if (total != null && (qty * unit - total).abs() > total * 0.02 + 1) {
      unit = total / qty; // Percaya total struk bila tidak cocok.
    }
    return (qty: qty, unit: unit);
  }

  /// Menafsirkan ekor angka sebuah baris barang menjadi jumlah, harga satuan, dan total.
  /// Mendukung antara lain: "12.000", "2 12.000", "6.000 12.000", "2 6.000 12.000",
  /// "2 x 6.000 12.000", dan "500.000 X1 500.000".
  _Interp? _interpret(List<_Num> nums, bool hasMarker, bool explicit) {
    final int n = nums.length;
    if (n == 0) return null;
    final List<double> v = nums.map((_Num x) => x.value).toList();

    if (hasMarker) {
      if (n == 1) return null;
      if (n == 2) {
        if (v[0] <= 0 || v[1] <= 0) return null;
        final double qty = v[0] <= v[1] ? v[0] : v[1];
        final double price = v[0] <= v[1] ? v[1] : v[0];
        if (explicit) {
          // "3 x 3.000": tanda kali tegas, angka lain adalah harga satuan.
          // Bila ternyata subtotal, total struk yang meluruskannya.
          return _Interp(qty, price, qty * price, '',
              altUnit: price / qty, altTotal: price);
        }
        // "2 SAK 130.000": tanpa tanda kali, angka terakhir lebih mungkin
        // subtotal (jumlah + satuan + total, tanpa harga satuan).
        return _Interp(qty, price / qty, price, '',
            altUnit: price, altTotal: qty * price);
      }
      final double a = v[n - 3];
      final double b = v[n - 2];
      final double total = v[n - 1];
      if (a <= 0 || b <= 0) return null;
      final ({double qty, double unit}) pair = _resolveQtyUnit(a, b, total);
      return _Interp(pair.qty, pair.unit, total, '');
    }

    if (n == 1) return _Interp(1, v[0], v[0], '');

    if (n == 2) {
      final double a = v[0];
      final double b = v[1];
      final String firstToken = nums[0].token;
      if (!_hasSeparator(firstToken) && a >= 1 && a <= 99) {
        // "2 12.000": 12.000 diperlakukan sebagai subtotal; bila total struk
        // tidak cocok, tafsirnya dibalik menjadi harga satuan.
        return _Interp(a, b / a, b, '', altUnit: b, altTotal: a * b);
      }
      if (_hasSeparator(firstToken) || a >= 1000) {
        final double q = a > 0 ? b / a : 1;
        if ((q - q.roundToDouble()).abs() < 0.01 &&
            q.round() >= 1 &&
            q.round() <= 99) {
          return _Interp(q.roundToDouble(), a, b, ''); // "6.000 12.000"
        }
        return _Interp(1, b, b, '');
      }
      return _Interp(1, b, b, firstToken); // 100-999 tanpa pemisah: bagian nama
    }

    final double x = v[n - 3];
    final double y = v[n - 2];
    final double z = v[n - 1];
    if (x > 0 && y > 0 && (x * y - z).abs() <= z * 0.02 + 1) {
      final double qty = x <= y ? x : y;
      final double unit = x <= y ? y : x;
      return _Interp(qty, unit, z, '');
    }
    final String suffix =
        nums.sublist(0, n - 1).map((_Num e) => e.token).join(' ');
    return _Interp(1, z, z, suffix);
  }

  ParsedItem? _buildItem(
    String nameRaw,
    List<_Num> nums,
    bool hasMarker, [
    bool? explicit,
  ]) {
    final _Interp? r = _interpret(nums, hasMarker, explicit ?? hasMarker);
    if (r == null) return null;
    if (r.total < _minAmount || r.total > _maxValue) return null;

    String name = '$nameRaw ${r.suffix}'.trim();
    double qty = r.qty;
    double unit = r.unit;
    double? altUnit = r.altUnit;
    double? altTotal = r.altTotal;
    bool known = hasMarker || nums.length >= 2;

    // Jumlah di awal nama ("2 TEH BOTOL 7.000").
    if (nums.length == 1 && !hasMarker) {
      final RegExpMatch? lead = _leadingQty.firstMatch(name);
      if (lead != null) {
        final int? q = int.tryParse(lead.group(1) ?? '');
        final String rest = name.substring(lead.end);
        if (q != null &&
            q >= 1 &&
            r.total / q >= _minAmount &&
            _letters(rest) >= 3) {
          qty = q.toDouble();
          unit = r.total / q;
          name = rest;
          known = true;
          // "2 TEH BOTOL 7.000": 7.000 subtotal, atau harga satuan?
          altUnit = r.total;
          altTotal = q * r.total;
        }
      }
    }

    final String? cleaned = _cleanItemName(name);
    if (cleaned == null) return null;

    ParsedItem? alternative;
    final double? at = altTotal;
    final double? au = altUnit;
    if (at != null &&
        au != null &&
        qty > 1 &&
        at <= _maxValue &&
        (at - r.total).abs() > 1) {
      alternative = ParsedItem(
        name: cleaned,
        quantity: qty,
        unitPrice: au,
        totalPrice: at,
      );
    }
    return ParsedItem(
      name: cleaned,
      quantity: qty,
      unitPrice: unit,
      totalPrice: r.total,
      alternative: alternative,
      quantityKnown: known,
    );
  }

  int _letters(String text) => RegExp(r'[A-Za-z]').allMatches(text).length;

  String? _cleanItemName(String raw) {
    final String withoutQty = raw.replaceAll(_qtyInName, ' ');
    final List<String> words = withoutQty.split(' ');
    final List<String> kept = <String>[];
    for (int k = 0; k < words.length; k++) {
      final String w = words[k];
      if (w.isEmpty) continue;
      // Angka setelah "Lv"/"Level"/"No" adalah bagian nama ("Mie Disko Lv 1").
      final bool partOfName = _numericWord.hasMatch(w) &&
          _smallInt.hasMatch(w) &&
          k > 0 &&
          _levelWord.hasMatch(words[k - 1]);
      if (!_numericWord.hasMatch(w) || partOfName) {
        kept.add(OcrTextCorrector.normalizeCase(w));
      }
    }
    final String name = kept
        .join(' ')
        .replaceAll(RegExp(r'^[^A-Za-z0-9]+'), '')
        .replaceAll(RegExp(r'[^A-Za-z0-9]+$'), '')
        .trim();

    if (_letters(name) < 3) return null;
    return name.length > 60 ? name.substring(0, 60).trim() : name;
  }
}
