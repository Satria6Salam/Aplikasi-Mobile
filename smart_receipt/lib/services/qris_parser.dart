import 'mcc_categories.dart';

/// Penyebab sebuah kode QR tidak dapat dibaca sebagai QRIS.
enum QrisError {
  /// Bukan QRIS/EMV QR (mis. QR situs web atau kontak).
  notQris,

  /// Susunan datanya rusak (panjang tidak cocok, terpotong).
  malformed,

  /// Kode pemeriksa (CRC) tidak cocok: QR rusak atau dimodifikasi.
  badChecksum,

  /// Tidak memuat nama merchant.
  missingMerchant,
}

class QrisParseException implements Exception {
  const QrisParseException(this.error);

  final QrisError error;

  String get message => switch (error) {
        QrisError.notQris => 'Ini bukan kode QRIS. Pindai kode QR milik toko.',
        QrisError.malformed => 'Kode QRIS tidak lengkap. Coba pindai ulang.',
        QrisError.badChecksum =>
          'Kode QRIS tidak valid (pemeriksa tidak cocok). Coba pindai ulang.',
        QrisError.missingMerchant =>
          'Kode QRIS ini tidak memuat nama toko, sehingga tidak bisa dicatat.',
      };

  @override
  String toString() => message;
}

/// Isi sebuah QRIS yang sudah dibaca.
class QrisData {
  const QrisData({
    required this.payload,
    required this.isDynamic,
    required this.merchantName,
    this.city,
    this.postalCode,
    this.mcc,
    this.merchantId,
    this.criteria,
    this.amount,
    this.fixedFee,
    this.percentFee,
    this.tipPrompt = false,
    this.storeLabel,
    this.billNumber,
  });

  /// Teks mentah QR.
  final String payload;

  /// True bila QR dibuat untuk satu transaksi (memuat nominal); QR statis
  /// (ditempel di meja/kasir) tidak memuat nominal.
  final bool isDynamic;

  final String merchantName;
  final String? city;
  final String? postalCode;

  /// Kode kategori merchant (4 digit), mis. 5812 = restoran.
  final String? mcc;

  /// NMID, nomor induk merchant nasional (mis. "ID1020012345678").
  final String? merchantId;

  /// Kriteria merchant: UMI, UKE, UME, UBE, atau DOM.
  final String? criteria;

  /// Nominal bila QR dinamis.
  final double? amount;

  /// Biaya layanan tetap (tag 56) atau persentase (tag 57), bila ada.
  final double? fixedFee;
  final double? percentFee;

  /// True bila pembayar diminta mengisi tip (tag 55).
  final bool tipPrompt;

  /// Label toko/cabang (tag 62 sub 03), bila ada.
  final String? storeLabel;
  final String? billNumber;

  bool get hasAmount => amount != null && amount! > 0;

  /// Nominal yang benar-benar dibayar: nominal ditambah biaya layanan.
  double? get totalAmount {
    final double? base = amount;
    if (base == null || base <= 0) return null;
    double total = base;
    if (fixedFee != null) total += fixedFee!;
    if (percentFee != null) total += base * percentFee! / 100;
    return total;
  }

  /// Nama kategori aplikasi untuk MCC QR ini.
  String get categoryName => MccCategories.of(mcc);

  /// Jenis usaha dalam kata-kata (mis. "Restoran"), bila MCC dikenal.
  String? get businessLabel => MccCategories.label(mcc);
}

/// Membaca QRIS (standar EMV QR Code Merchant-Presented Mode, format TLV).
///
/// Setiap data berbentuk `TTLL<nilai>`: 2 digit tag, 2 digit panjang, lalu
/// nilainya. Tag penting: 01 jenis QR (11 statis, 12 dinamis), 26-51 akun
/// merchant (51 = QRIS nasional berisi NMID), 52 MCC, 54 nominal, 56/57 biaya,
/// 58 negara, 59 nama merchant, 60 kota, 61 kode pos, 62 data tambahan,
/// dan 63 CRC16 untuk memastikan QR tidak rusak.
class QrisParser {
  const QrisParser();

  /// Membaca [payload]. Melempar [QrisParseException] bila bukan QRIS valid.
  QrisData parse(String payload) {
    final String text = payload.trim();
    if (!text.startsWith('000201')) {
      throw const QrisParseException(QrisError.notQris);
    }

    final Map<String, String> root = _tlv(text);
    if (root['00'] != '01') throw const QrisParseException(QrisError.notQris);

    _verifyChecksum(text);

    final String? name = _clean(root['59']);
    if (name == null || name.isEmpty) {
      throw const QrisParseException(QrisError.missingMerchant);
    }

    // Akun merchant: 51 = QRIS nasional; 26-45 = akun penyelenggara.
    String? nmid;
    String? criteria;
    for (int tag = 26; tag <= 51; tag++) {
      final String? template = root[tag.toString().padLeft(2, '0')];
      if (template == null) continue;
      final Map<String, String> sub = _tlvLoose(template);
      final String domain = (sub['00'] ?? '').toUpperCase();
      if (domain.contains('QRIS') || tag == 51) {
        nmid ??= _clean(sub['02']);
        criteria ??= _clean(sub['03']);
      }
    }
    // Cadangan: nomor akun merchant pada template penyelenggara.
    nmid ??= () {
      for (int tag = 26; tag <= 45; tag++) {
        final String? template = root[tag.toString().padLeft(2, '0')];
        if (template == null) continue;
        final String? pan = _clean(_tlvLoose(template)['01']);
        if (pan != null && pan.isNotEmpty) return pan;
      }
      return null;
    }();

    final Map<String, String> extra = _tlvLoose(root['62'] ?? '');

    return QrisData(
      payload: text,
      isDynamic: root['01'] == '12',
      merchantName: _title(name),
      city: _titleOrNull(root['60']),
      postalCode: _clean(root['61']),
      mcc: _clean(root['52']),
      merchantId: nmid,
      criteria: criteria,
      amount: _amount(root['54']),
      fixedFee: root['55'] == '02' ? _amount(root['56']) : null,
      percentFee: root['55'] == '03' ? _amount(root['57']) : null,
      tipPrompt: root['55'] == '01',
      storeLabel: _titleOrNull(extra['03']),
      billNumber: _clean(extra['01']),
    );
  }

  /// True bila [payload] tampak seperti QRIS (untuk menyaring hasil pemindai
  /// sebelum dibaca penuh).
  bool looksLikeQris(String payload) => payload.trim().startsWith('000201');

  // ------------------------------------------------------------- TLV

  /// Memecah TLV tingkat atas; melempar bila panjang tidak cocok.
  Map<String, String> _tlv(String text) {
    final Map<String, String> out = <String, String>{};
    int i = 0;
    while (i < text.length) {
      if (i + 4 > text.length) {
        throw const QrisParseException(QrisError.malformed);
      }
      final String tag = text.substring(i, i + 2);
      final int? length = int.tryParse(text.substring(i + 2, i + 4));
      if (length == null || i + 4 + length > text.length) {
        throw const QrisParseException(QrisError.malformed);
      }
      out[tag] = text.substring(i + 4, i + 4 + length);
      i += 4 + length;
    }
    return out;
  }

  /// TLV untuk template bersarang: bagian yang rusak diabaikan, bukan galat.
  Map<String, String> _tlvLoose(String text) {
    try {
      return _tlv(text);
    } on QrisParseException {
      return <String, String>{};
    }
  }

  // ------------------------------------------------------------- CRC

  /// CRC-16/CCITT-FALSE (polinomial 0x1021, awal 0xFFFF) dari [data].
  static int crc16(String data) {
    int crc = 0xFFFF;
    for (final int unit in data.codeUnits) {
      crc ^= (unit & 0xFF) << 8;
      for (int bit = 0; bit < 8; bit++) {
        crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
        crc &= 0xFFFF;
      }
    }
    return crc;
  }

  /// CRC sebagai 4 karakter heksadesimal huruf besar.
  static String crcHex(String data) =>
      crc16(data).toRadixString(16).toUpperCase().padLeft(4, '0');

  void _verifyChecksum(String text) {
    // Tag 63 selalu terakhir: "6304" + 4 digit heksadesimal.
    if (text.length < 8 ||
        text.substring(text.length - 8, text.length - 4) != '6304') {
      throw const QrisParseException(QrisError.badChecksum);
    }
    final String given = text.substring(text.length - 4).toUpperCase();
    final String computed = crcHex(text.substring(0, text.length - 4));
    if (given != computed) {
      throw const QrisParseException(QrisError.badChecksum);
    }
  }

  /// Membuat QRIS valid dari [fields] (tag -> nilai); dipakai pengujian dan
  /// contoh. CRC dihitung otomatis.
  static String build(Map<String, String> fields) {
    final StringBuffer body = StringBuffer();
    fields.forEach((String tag, String value) {
      body.write('$tag${value.length.toString().padLeft(2, '0')}$value');
    });
    body.write('6304');
    final String partial = body.toString();
    return '$partial${crcHex(partial)}';
  }

  // ------------------------------------------------------ pembersihan

  String? _clean(String? value) {
    final String v = (value ?? '').trim();
    return v.isEmpty ? null : v;
  }

  double? _amount(String? value) {
    final String? v = _clean(value);
    if (v == null) return null;
    final double? parsed = double.tryParse(v.replaceAll(',', '.'));
    return (parsed == null || parsed < 0) ? null : parsed;
  }

  String? _titleOrNull(String? value) {
    final String? v = _clean(value);
    return v == null ? null : _title(v);
  }

  /// "WARUNG BU SITI" -> "Warung Bu Siti"; nama yang sudah bercampur huruf
  /// kecil dibiarkan.
  String _title(String value) {
    final String v = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    final bool allUpper = v == v.toUpperCase() && RegExp(r'[A-Z]').hasMatch(v);
    if (!allUpper) return v;
    return v
        .split(' ')
        .map((String w) =>
            w.isEmpty ? w : '${w[0]}${w.substring(1).toLowerCase()}')
        .join(' ');
  }
}
