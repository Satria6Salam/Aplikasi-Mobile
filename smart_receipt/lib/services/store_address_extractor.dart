/// Ekstraksi nama cabang dan alamat toko dari teks mentah OCR struk.
///
/// Alur:
/// 1. Batasi pencarian ke kepala struk (sebelum baris tanggal/barang).
/// 2. Beri skor setiap baris berdasarkan ciri alamat Indonesia
///    (Jl., RT/RW, Kel., Kec., Kab./Kota, kode pos, nama kota).
/// 3. Gabungkan baris berurutan menjadi blok, lalu pilih blok terbaik.
///    Struk jaringan ritel sering memuat alamat kantor pusat (mis. "Gedung
///    Menara Indomaret, Jakarta Utara") di atas alamat cabang; blok setelah
///    NPWP dan yang paling dekat dengan baris tanggal diutamakan.
/// 4. Normalisasi (perbaiki salah baca OCR, perluas singkatan) dan pecah
///    menjadi komponen: jalan, nomor, RT/RW, kelurahan, kecamatan, kota,
///    provinsi, kode pos.
library;

import 'indonesian_places.dart';

/// Tingkat ketelitian sebuah lokasi, dari paling rinci ke paling kasar.
enum LocationPrecision { store, street, village, district, postalCode, city }

/// Label tampilan tingkat ketelitian.
extension LocationPrecisionLabel on LocationPrecision {
  String get label => switch (this) {
        LocationPrecision.store => 'tingkat toko',
        LocationPrecision.street => 'tingkat jalan',
        LocationPrecision.village => 'tingkat kelurahan/desa',
        LocationPrecision.district => 'tingkat kecamatan',
        LocationPrecision.postalCode => 'tingkat kode pos',
        LocationPrecision.city => 'tingkat kota',
      };
}

/// Satu kueri geocoding beserta tingkat ketelitian yang diharapkan.
class AddressQuery {
  const AddressQuery(this.text, this.precision);

  final String text;
  final LocationPrecision precision;

  @override
  String toString() => '$precision: $text';
}

/// Komponen alamat toko hasil ekstraksi.
class StoreAddress {
  const StoreAddress({
    this.branchName,
    this.street,
    this.houseNumber,
    this.rtRw,
    this.village,
    this.district,
    this.city,
    this.province,
    this.postalCode,
    this.phone,
    this.rawLines = const <String>[],
    this.confidence = 0,
    this.freeText,
  });

  /// Alamat apa adanya (sudah dirapikan) bila komponennya tidak dapat
  /// dipecah, supaya kolom alamat tetap terisi dan bisa diperbaiki pengguna.
  final String? freeText;

  /// Nama cabang (mis. "Urek Urek" pada struk Indomaret).
  final String? branchName;

  /// Nama jalan lengkap, mis. "Jalan Raya Urek Urek".
  final String? street;
  final String? houseNumber;

  /// Format "RT 02/RW 05".
  final String? rtRw;
  final String? village;

  /// Mis. "Gondanglegi" (tanpa awalan "Kecamatan").
  final String? district;

  /// Termasuk jenisnya, mis. "Kabupaten Malang" atau "Kota Bandung".
  final String? city;
  final String? province;
  final String? postalCode;
  final String? phone;

  /// Baris asli struk yang dipakai sebagai sumber alamat.
  final List<String> rawLines;

  /// Keyakinan ekstraksi 0..1 (berdasarkan kelengkapan komponen).
  final double confidence;

  static const StoreAddress empty = StoreAddress();

  bool get hasComponents =>
      street != null ||
      village != null ||
      district != null ||
      city != null ||
      postalCode != null;

  bool get isEmpty => !hasComponents && (freeText ?? '').isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// Nama kota tanpa awalan "Kabupaten"/"Kota" (untuk pencocokan).
  String? get cityName => city?.replaceFirst(
      RegExp(r'^(?:Kabupaten|Kota|Kota Administrasi)\s+'), '');

  /// Alamat lengkap untuk ditampilkan dan disimpan.
  String get fullAddress {
    if (!hasComponents) return freeText ?? '';
    final String? streetPart = street == null
        ? null
        : (houseNumber == null ? street : '$street No. $houseNumber');
    final String? districtPart =
        district == null ? null : 'Kecamatan $district';
    final String? cityPart =
        city == null ? null : (postalCode == null ? city : '$city $postalCode');
    return <String?>[
      streetPart,
      rtRw,
      village,
      districtPart,
      cityPart ?? postalCode,
      province,
    ].whereType<String>().where((String s) => s.isNotEmpty).join(', ');
  }

  /// Kueri bertingkat, dari paling rinci ke paling kasar. Nomor rumah dan
  /// RT/RW sengaja tidak disertakan karena jarang tercatat di peta.
  List<AddressQuery> geocodeQueries(String? merchantName) {
    final List<AddressQuery> queries = <AddressQuery>[];
    final Set<String> seen = <String>{};

    void add(List<String?> parts, LocationPrecision precision) {
      final List<String> filled = parts
          .whereType<String>()
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .toList();
      if (filled.isEmpty) return;
      final String text = filled.join(', ');
      if (seen.add(text.toLowerCase())) {
        queries.add(AddressQuery(text, precision));
      }
    }

    final String? free = freeText;
    if (!hasComponents && free != null && free.isNotEmpty) {
      add(<String?>[free], LocationPrecision.street);
      return queries;
    }
    // Catatan dari uji API sungguhan: Nominatim mewajibkan SEMUA kata cocok,
    // sehingga kueri dibuat pendek, dan awalan "Kecamatan" justru membuat
    // hasil kosong ("Gondanglegi, Kabupaten Malang" berhasil, sedangkan
    // "Kecamatan Gondanglegi, Kabupaten Malang" tidak).
    final String merchant = (merchantName ?? '').trim();
    if (merchant.isNotEmpty) {
      // Toko di OSM biasanya bernama "Indomaret" saja, jadi nama toko
      // dipadukan dengan cabang/kelurahan/kecamatan, bukan alamat lengkap.
      if (branchName != null) {
        add(<String?>['$merchant $branchName', city], LocationPrecision.store);
      }
      final String? area = village ?? district;
      if (area != null && area != branchName) {
        add(<String?>['$merchant $area', city], LocationPrecision.store);
      }
      if (district != null && district != area) {
        add(<String?>['$merchant $district', city], LocationPrecision.store);
      }
      // Hanya nama toko dan kota (mis. dari QRIS yang tidak memuat alamat).
      if (city != null &&
          !queries.any(
              (AddressQuery q) => q.precision == LocationPrecision.store)) {
        add(<String?>[merchant, city], LocationPrecision.store);
      }
    }
    if (street != null) {
      add(<String?>[street, district, city], LocationPrecision.street);
      add(<String?>[street, city], LocationPrecision.street);
      // "Jalan Raya X" sering tercatat di peta sebagai "Jalan X".
      if (street!.contains(' Raya ')) {
        add(<String?>[street!.replaceFirst(' Raya ', ' '), city],
            LocationPrecision.street);
      }
    }
    if (village != null) {
      add(<String?>[village, district, city], LocationPrecision.village);
      add(<String?>[village, district], LocationPrecision.village);
    }
    if (district != null) {
      add(<String?>[district, city], LocationPrecision.district);
    }
    if (postalCode != null) {
      add(<String?>[postalCode, city], LocationPrecision.postalCode);
    }
    if (city != null) add(<String?>[city, province], LocationPrecision.city);
    return queries;
  }

  /// Melengkapi bagian yang kosong dengan petunjuk dari judul toko (mis.
  /// "Wizzmie Muharto Malang" -> cabang Muharto, Jalan Muharto, kota Malang).
  /// Yang sudah terbaca dari baris alamat tidak ditimpa.
  StoreAddress merged({String? branchName, String? street, String? city}) {
    final bool adds = (this.branchName == null && branchName != null) ||
        (this.street == null && street != null) ||
        (this.city == null && city != null);
    if (!adds) return this;
    final StoreAddress base = StoreAddress(
      branchName: this.branchName ?? branchName,
      street: this.street ?? street,
      houseNumber: houseNumber,
      rtRw: rtRw,
      village: village,
      district: district,
      city: this.city ?? city,
      province: province,
      postalCode: postalCode,
      phone: phone,
      rawLines: rawLines,
      freeText: freeText,
    );
    return base.copyWith(confidence: _scoreOf(base));
  }

  static double _scoreOf(StoreAddress a) {
    double c = 0;
    if (a.street != null) c += 0.35;
    if (a.district != null) c += 0.2;
    if (a.city != null) c += 0.2;
    if (a.postalCode != null) c += 0.15;
    if (a.village != null) c += 0.05;
    if (a.houseNumber != null) c += 0.05;
    return c > 1 ? 1 : c;
  }

  StoreAddress copyWith({String? branchName, double? confidence}) {
    return StoreAddress(
      branchName: branchName ?? this.branchName,
      street: street,
      houseNumber: houseNumber,
      rtRw: rtRw,
      village: village,
      district: district,
      city: city,
      province: province,
      postalCode: postalCode,
      phone: phone,
      rawLines: rawLines,
      confidence: confidence ?? this.confidence,
      freeText: freeText,
    );
  }

  @override
  String toString() => fullAddress;
}

class _Line {
  _Line(this.index, this.text);

  final int index;
  final String text;
  double score = 0;
  bool noise = false;
}

/// Pengambil alamat toko dari teks struk (tanpa internet, murni Dart).
class StoreAddressExtractor {
  const StoreAddressExtractor();

  static const int _headerLimit = 22;
  static const int _footerLimit = 12;

  // ------------------------------------------------------------- pola baris
  static final RegExp _street = RegExp(
      r'(?:^|[\s,(])(?:jalan|jln|j[li1])\b\.?|\bjl\.',
      caseSensitive: false);
  static final RegExp _boulevard =
      RegExp(r'\b(?:boulevard|blvd|bulevar)\b', caseSensitive: false);
  static final RegExp _houseNo = RegExp(r'\bno\.?\s*\d', caseSensitive: false);
  static final RegExp _rtRwKey = RegExp(
      r'\brt\b\.?\s*\d|\brw\b\.?\s*\d|\brt\s*/\s*rw\b',
      caseSensitive: false);
  static final RegExp _villageKey = RegExp(
      r'\b(?:kel|kelurahan|desa|ds|dusun|dsn)\b\.?',
      caseSensitive: false);
  static final RegExp _districtKey =
      RegExp(r'\b(?:kec|kecamatan|kcm)\b\.?', caseSensitive: false);
  static final RegExp _cityKey = RegExp(
      r'\b(?:kab|ka[bpr]u?pat[eéf]n|kabupatn|kota|kodya|kotamadya)\b\.?',
      caseSensitive: false);
  static final RegExp _provinceKey =
      RegExp(r'\b(?:prov|provinsi|propinsi)\b\.?', caseSensitive: false);
  static final RegExp _buildingKey = RegExp(
      r'\b(?:ruko|rukan|komp|komplek|kompleks|perum|perumahan|blok|gedung|gd|mall|mal|plaza|pasar|ps|square|apartemen|tower|kav|kavling|gang|gg|kampung|kp|kawasan|terminal|stasiun|bandara|pertokoan|lantai)\b\.?',
      caseSensitive: false);
  static final RegExp _addressLabel = RegExp(
      r'^\s*(?:alamat|addr|address|lokasi)\b\s*[:\-]?\s*',
      caseSensitive: false);
  static final RegExp _priceTail = RegExp(r'\s\d{4,}(?:[.,]\d{1,2})?$');
  static final RegExp _postal = RegExp(r'(?<![\d.,])(\d{5})(?![\d.,])');
  static final RegExp _amount = RegExp(r'\d{1,3}(?:[.,]\d{3})+(?![\d])');

  static final RegExp _phone = RegExp(
      r'\b(?:telp|tlp|tel|telepon|phone|hp|wa|fax|call)\b|\(0\d{2,3}\)|\b0\d{2,3}[\s-]?\d{5,}',
      caseSensitive: false);
  static final RegExp _npwp =
      RegExp(r'\bnp[wv]{1,2}p\b|\bnpwp\b', caseSensitive: false);
  static final RegExp _web = RegExp(
      r'www|http|\.com|\.co\.id|@|instagram|ig\s*:',
      caseSensitive: false);
  static final RegExp _otherNoise = RegExp(
      r'\b(?:kasir|cashier|struk|faktur|invoice|no\.?\s*(?:trx|transaksi|nota|struk)|member|selamat|welcome|terima\s*kasih|thank)\b',
      caseSensitive: false);
  static final RegExp _companyLine =
      RegExp(r'^\(?\s*(?:pt|cv|ud|pd)\b\.?\s', caseSensitive: false);
  static final RegExp _headOffice = RegExp(
      r'\b(?:kantor\s*pusat|head\s*office|gedung\s*menara|menara)\b',
      caseSensitive: false);

  static final RegExp _date = RegExp(
    r'(?<!\d)\d{1,4}[/\-.]\d{1,2}[/\-.]\d{2,4}(?!\d)|(?<!\d)\d{1,2}\s*(?:jan|feb|mar|apr|mei|may|jun|jul|agu|aug|sep|okt|oct|nov|des|dec)[a-z]*\.?\s*,?\s*\d{2,4}',
    caseSensitive: false,
  );
  static final RegExp _itemOrTotal = RegExp(
      r'\b(?:total|subtotal|jumlah|tunai|cash|qty|harga)\b',
      caseSensitive: false);

  /// Mengambil alamat dari [rawText]. [merchantName] dipakai agar baris nama
  /// toko tidak dianggap nama cabang.
  StoreAddress extract(String rawText, {String? merchantName}) {
    final List<String> raw = _rawLines(rawText);
    if (raw.isEmpty) return StoreAddress.empty;

    // Alamat umumnya di kepala struk; sebagian struk menaruhnya di kaki.
    final StoreAddress fromHeader =
        _extractFrom(_header(raw), merchantName, minScore: 2);
    if (fromHeader.isNotEmpty) return fromHeader;
    return _extractFrom(_footer(raw), merchantName, minScore: 5);
  }

  StoreAddress _extractFrom(
    List<_Line> lines,
    String? merchantName, {
    required double minScore,
  }) {
    if (lines.isEmpty) return StoreAddress.empty;

    for (final _Line line in lines) {
      line.noise = _isNoise(line.text);
      line.score = line.noise ? 0 : _score(line.text);
    }

    final List<List<_Line>> blocks = _blocks(lines);
    if (blocks.isEmpty) return StoreAddress.empty;

    final int npwpIndex = lines
        .lastWhere((_Line l) => _npwp.hasMatch(l.text),
            orElse: () => _Line(-1, ''))
        .index;
    final List<_Line> best = _chooseBlock(blocks, lines, npwpIndex);
    final double blockScore =
        best.fold<double>(0, (double sum, _Line l) => sum + l.score);
    if (blockScore < minScore) return StoreAddress.empty;

    final StoreAddress parsed = _parseComponents(best);
    final String freeText = parsed.hasComponents
        ? ''
        : best
            .map((_Line l) => _titleCase(_clean(_normalize(l.text))))
            .where((String t) => t.isNotEmpty)
            .join(', ');
    if (!parsed.hasComponents && freeText.isEmpty) return StoreAddress.empty;

    final String? branch = _branchBefore(lines, best.first, merchantName);
    final String? phone = _phoneNear(lines, best);
    final StoreAddress withExtras = StoreAddress(
      branchName: branch,
      street: parsed.street,
      houseNumber: parsed.houseNumber,
      rtRw: parsed.rtRw,
      village: parsed.village,
      district: parsed.district,
      city: parsed.city,
      province: parsed.province,
      postalCode: parsed.postalCode,
      phone: phone,
      rawLines: best.map((_Line l) => l.text).toList(),
      freeText: freeText.isEmpty ? null : freeText,
    );
    return withExtras.copyWith(confidence: _confidence(withExtras));
  }

  // ---------------------------------------------------------- kepala struk

  List<String> _rawLines(String rawText) => rawText
      .split(RegExp(r'\r?\n'))
      .map((String l) => l
          .replaceAll(RegExp(r'\.{2,}|_{2,}|-{3,}|={2,}|\*{2,}'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim())
      .where((String l) => l.isNotEmpty)
      .toList();

  /// Kepala struk: dari baris pertama sampai baris barang/total pertama.
  /// Baris tanggal TIDAK mengakhiri kepala (sebagian struk menaruh tanggal
  /// sebelum alamat); baris itu hanya dianggap derau.
  List<_Line> _header(List<String> raw) {
    final List<_Line> out = <_Line>[];
    for (int i = 0; i < raw.length && i < _headerLimit; i++) {
      final String line = raw[i];
      final bool addressish = _score(line) >= 2;
      if (!addressish && _itemOrTotal.hasMatch(line)) break;
      if (!addressish && out.length >= 2 && !_phone.hasMatch(line)) {
        if (_amount.hasMatch(line) || _priceTail.hasMatch(line)) break;
      }
      out.add(_Line(i, line));
    }
    return out;
  }

  /// Kaki struk: beberapa baris terakhir yang bukan baris harga/total.
  List<_Line> _footer(List<String> raw) {
    final int from = raw.length > _footerLimit ? raw.length - _footerLimit : 0;
    final List<_Line> out = <_Line>[];
    for (int i = from; i < raw.length; i++) {
      final String line = raw[i];
      final bool addressish = _score(line) >= 2;
      if (!addressish &&
          !_phone.hasMatch(line) &&
          (_itemOrTotal.hasMatch(line) ||
              _amount.hasMatch(line) ||
              _priceTail.hasMatch(line))) {
        out.add(_Line(i, '')..noise = true); // Penyekat antarblok.
        continue;
      }
      out.add(_Line(i, line));
    }
    return out;
  }

  bool _isNoise(String line) {
    if (line.isEmpty) return true;
    if (_npwp.hasMatch(line) || _web.hasMatch(line)) return true;
    // Baris tanggal/jam tanpa kata kunci alamat adalah derau.
    if (_date.hasMatch(line) && _score(line) < 2) return true;
    if (_otherNoise.hasMatch(line)) return true;
    // Baris telepon murni (tanpa kata kunci alamat) adalah derau.
    if (_phone.hasMatch(line) &&
        !_street.hasMatch(line) &&
        !_districtKey.hasMatch(line) &&
        !_cityKey.hasMatch(line)) {
      return true;
    }
    return false;
  }

  /// Skor kemiripan baris dengan alamat.
  double _score(String line) {
    double s = 0;
    if (_addressLabel.hasMatch(line)) s += 3;
    if (_street.hasMatch(line)) s += 4;
    if (_boulevard.hasMatch(line)) s += 3;
    if (_houseNo.hasMatch(line)) s += 1;
    if (_rtRwKey.hasMatch(line)) s += 2;
    if (_villageKey.hasMatch(line)) s += 3;
    if (_districtKey.hasMatch(line)) s += 3;
    if (_cityKey.hasMatch(line)) s += 3;
    if (_provinceKey.hasMatch(line)) s += 2;
    if (_buildingKey.hasMatch(line)) s += 2;
    if (_postal.hasMatch(line) &&
        !_amount.hasMatch(line) &&
        !RegExp(r'\d{6,}').hasMatch(line)) {
      s += 3;
    }
    if (_matchKnown(line, IndonesianPlaces.cities) != null) s += 2;
    if (_matchKnown(line, IndonesianPlaces.provinces) != null) s += 2;
    return s;
  }

  /// Baris berurutan yang mirip alamat digabung menjadi blok. Baris pendek
  /// tanpa kata kunci (mis. "PANTAI INDAH KAPUK") ikut bila diapit atau
  /// tepat setelah baris alamat. Baris derau (NPWP, telepon) memutus blok.
  List<List<_Line>> _blocks(List<_Line> lines) {
    final List<List<_Line>> blocks = <List<_Line>>[];
    List<_Line> current = <_Line>[];

    void close() {
      // Buang baris lanjutan (skor 0) di ujung blok.
      while (current.isNotEmpty && current.last.score == 0) {
        current.removeLast();
      }
      if (current.isNotEmpty) blocks.add(current);
      current = <_Line>[];
    }

    for (int i = 0; i < lines.length; i++) {
      final _Line line = lines[i];
      if (line.noise) {
        close();
        continue;
      }
      if (line.score >= 2) {
        current.add(line);
        continue;
      }
      final bool continuation = current.isNotEmpty &&
          _looksLikePlaceName(line.text) &&
          i + 1 < lines.length &&
          !lines[i + 1].noise &&
          lines[i + 1].score >= 2;
      if (continuation) {
        current.add(line);
      } else {
        close();
      }
    }
    close();
    return blocks;
  }

  bool _looksLikePlaceName(String line) {
    if (line.length > 32) return false;
    final int letters = RegExp(r'[A-Za-z]').allMatches(line).length;
    final int visible = line.replaceAll(' ', '').length;
    return visible > 0 && letters / visible >= 0.75;
  }

  List<_Line> _chooseBlock(
      List<List<_Line>> blocks, List<_Line> lines, int npwpIndex) {
    final int lastIndex = lines.last.index;
    List<_Line> best = blocks.first;
    double bestScore = double.negativeInfinity;
    for (final List<_Line> block in blocks) {
      double s = block.fold<double>(0, (double sum, _Line l) => sum + l.score);
      final String text = block.map((_Line l) => l.text).join(' ');
      // Alamat cabang biasanya setelah NPWP dan paling dekat ke isi struk.
      if (npwpIndex >= 0 && block.first.index > npwpIndex) s += 4;
      s += 2 * (block.last.index / (lastIndex == 0 ? 1 : lastIndex));
      if (_headOffice.hasMatch(text)) s -= 4;
      final int before = block.first.index - 1;
      if (before >= 0 &&
          lines.any((_Line l) =>
              l.index == before && _companyLine.hasMatch(l.text))) {
        s -= 3; // Alamat tepat di bawah nama PT = alamat badan usaha.
      }
      if (s >= bestScore) {
        bestScore = s;
        best = block;
      }
    }
    return best;
  }

  String? _branchBefore(List<_Line> lines, _Line first, String? merchant) {
    final int pos = lines.indexOf(first);
    if (pos <= 0) return null;
    final _Line prev = lines[pos - 1];
    if (prev.noise || prev.score > 0) return null;
    if (_companyLine.hasMatch(prev.text) || !_looksLikePlaceName(prev.text)) {
      return null;
    }
    // Baris pertama yang berhuruf adalah nama toko, bukan cabang.
    final int merchantPos = lines.indexWhere(
        (_Line l) => !l.noise && RegExp(r'[A-Za-z]{3}').hasMatch(l.text));
    if (pos - 1 <= merchantPos) return null;
    final String m = _key(merchant ?? '');
    final String p = _key(prev.text);
    if (m.isNotEmpty && (p == m || p.contains(m) && p.length - m.length < 3)) {
      return null;
    }
    // "INDOMARET UREK UREK" -> "Urek Urek".
    String text = prev.text;
    if (m.isNotEmpty && p.startsWith(m)) {
      text = text.substring(text.toLowerCase().indexOf(m.split(' ').last) +
          m.split(' ').last.length);
    }
    final String cleaned = _titleCase(_clean(text));
    return cleaned.length < 3 ? null : cleaned;
  }

  String? _phoneNear(List<_Line> lines, List<_Line> block) {
    final int from = block.first.index - 1;
    final int to = block.last.index + 2;
    for (final _Line l in lines) {
      if (l.index < from || l.index > to) continue;
      final RegExpMatch? m =
          RegExp(r'(\(?0\d{2,4}\)?[\s-]?\d{3,4}[\s-]?\d{3,5})')
              .firstMatch(l.text);
      if (m != null && _phone.hasMatch(l.text)) {
        return m.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
      }
    }
    return null;
  }

  double _confidence(StoreAddress a) {
    double c = 0;
    if (a.street != null) c += 0.35;
    if (a.district != null) c += 0.2;
    if (a.city != null) c += 0.2;
    if (a.postalCode != null) c += 0.15;
    if (a.village != null) c += 0.05;
    if (a.houseNumber != null) c += 0.05;
    return c > 1 ? 1 : c;
  }

  // ------------------------------------------------------- pecah komponen

  StoreAddress _parseComponents(List<_Line> block) {
    String text = block.map((_Line l) => _normalize(l.text)).join(', ');
    text = text.replaceAll(RegExp(r'\s*,\s*(?:,\s*)+'), ', ');

    String? take(RegExp pattern, {int group = 1}) {
      final RegExpMatch? m = pattern.firstMatch(text);
      if (m == null) return null;
      final String value = (m.group(group) ?? '').trim();
      text = text.replaceRange(m.start, m.end, ', ');
      return value.isEmpty ? null : value;
    }

    // Batas akhir sebuah komponen: koma, kata kunci komponen lain, atau angka.
    const String stop =
        r'(?=\s*(?:,|$|\b(?:Jalan|RT|RW|Kelurahan|Desa|Dusun|Kecamatan|Kabupaten|Kota|Provinsi|No)\b|\d))';

    final String? postal = () {
      final List<RegExpMatch> all = _postal.allMatches(text).toList();
      if (all.isEmpty) return null;
      final RegExpMatch m = all.last;
      text = text.replaceRange(m.start, m.end, ' ');
      return m.group(1);
    }();

    String? rtRw;
    final RegExpMatch? rt = RegExp(
            r'\bRT\b\.?\s*0*(\d{1,3})\s*(?:/|,|\s)\s*(?:RW\b\.?\s*)?0*(\d{1,3})',
            caseSensitive: false)
        .firstMatch(text);
    if (rt != null) {
      rtRw =
          'RT ${rt.group(1)!.padLeft(2, '0')}/RW ${rt.group(2)!.padLeft(2, '0')}';
      text = text.replaceRange(rt.start, rt.end, ', ');
    }

    final String? district =
        take(RegExp('\\bKecamatan\\s+([A-Za-z][A-Za-z .\'-]*?)$stop'));
    final String? cityRaw = () {
      final RegExpMatch? m =
          RegExp('\\b(Kabupaten|Kota)\\s+([A-Za-z][A-Za-z .\'-]*?)$stop')
              .firstMatch(text);
      if (m == null) return null;
      text = text.replaceRange(m.start, m.end, ', ');
      return '${m.group(1)} ${_fixCity(m.group(2)!.trim())}';
    }();
    final String? village = take(RegExp(
        '\\b(?:Kelurahan|Desa|Dusun)\\s+([A-Za-z][A-Za-z .\'-]*?)$stop'));
    String? province =
        take(RegExp('\\bProvinsi\\s+([A-Za-z][A-Za-z .\'-]*?)$stop'));

    String? street;
    String? houseNo;
    final RegExpMatch? st = RegExp(
            r'\bJalan\s+(.+?)(?=\s*(?:,|$|\b(?:RT|RW|Kelurahan|Desa|Kecamatan|Kabupaten|Kota|Provinsi)\b))')
        .firstMatch(text);
    if (st != null) {
      String body = st.group(1)!.trim();
      final RegExpMatch? no = RegExp(
              r'\bNo\b\.?\s*([0-9]+[A-Za-z]?(?:\s*[-/]\s*[0-9A-Za-z]+)?)?',
              caseSensitive: false)
          .firstMatch(body);
      if (no != null) {
        houseNo = no.group(1)?.replaceAll(' ', '');
        body = body.replaceRange(no.start, no.end, ' ');
      }
      body = _clean(body);
      if (RegExp(r'[A-Za-z]{2}').hasMatch(body)) street = 'Jalan $body';
      text = text.replaceRange(st.start, st.end, ', ');
    } else {
      // Tanpa "Jalan": pakai nama gedung/ruko sebagai patokan jalan.
      final RegExpMatch? b = RegExp(
              '\\b((?:Ruko|Rukan|Komplek|Perumahan|Blok|Gedung|Mall|Plaza|Pasar|Square|Boulevard|Gang|Kampung|Pertokoan|Terminal|Stasiun|Kawasan)\\b[^,]*)',
              caseSensitive: false)
          .firstMatch(text);
      if (b != null) {
        String body = b.group(1)!;
        final RegExpMatch? no = RegExp(
                r'\bNo\b\.?\s*([0-9]+[A-Za-z]?(?:\s*[-/]\s*[0-9A-Za-z]+)?)',
                caseSensitive: false)
            .firstMatch(body);
        if (no != null) {
          houseNo = no.group(1)?.replaceAll(' ', '');
          body = body.replaceRange(no.start, no.end, ' ');
        }
        street = _clean(body);
        text = text.replaceRange(b.start, b.end, ', ');
      }
    }

    // Sisa potongan tanpa kata kunci: kota/provinsi dikenal, atau kelurahan.
    String? city = cityRaw;
    String? leftoverVillage;
    for (final String part in text.split(',')) {
      final String seg = _clean(part);
      if (seg.length < 3 || !RegExp(r'[A-Za-z]{3}').hasMatch(seg)) continue;
      final String? prov = _matchKnown(seg, IndonesianPlaces.provinces);
      if (prov != null && province == null) {
        province = prov;
        continue;
      }
      final String? known = _matchKnown(seg, IndonesianPlaces.cities);
      if (known != null && city == null) {
        city = known;
        continue;
      }
      if (known != null) continue;
      if (leftoverVillage == null &&
          (street != null || district != null) &&
          _looksLikePlaceName(seg) &&
          !_buildingKey.hasMatch(seg)) {
        leftoverVillage = seg;
      }
    }

    String? tc(String? s) => s == null ? null : _titleCase(s);
    return StoreAddress(
      street: tc(street),
      houseNumber: houseNo?.toUpperCase(),
      rtRw: rtRw,
      village: tc(village ?? leftoverVillage),
      district: tc(district),
      city: tc(city),
      province: province == null ? null : _titleCase(province),
      postalCode: postal,
    );
  }

  /// Memperbaiki salah baca OCR pada kata kunci dan memperluas singkatan.
  String _normalize(String line) {
    String s = line.replaceFirst(_addressLabel, '');
    // "JI." / "J1." / "Jln" -> "Jalan".
    s = s.replaceAllMapped(
        RegExp(r'(^|[\s,(])(?:jalan|jln|jl|j[I1])\b\.?\s*',
            caseSensitive: false),
        (Match m) => '${m.group(1)}Jalan ');
    s = s.replaceAll(
        RegExp(r'\b(?:kab|ka[bpr]u?pat[eéf]n|kabupatn)\b\.?\s*',
            caseSensitive: false),
        'Kabupaten ');
    s = s.replaceAll(
        RegExp(r'\b(?:kota|kodya|kotamadya)\b\.?\s*', caseSensitive: false),
        'Kota ');
    s = s.replaceAll(
        RegExp(r'\b(?:kec|kecamatan|kcm)\b\.?\s*', caseSensitive: false),
        'Kecamatan ');
    s = s.replaceAll(
        RegExp(r'\b(?:kel|kelurahan)\b\.?\s*', caseSensitive: false),
        'Kelurahan ');
    s = s.replaceAll(
        RegExp(r'\b(?:ds|desa)\b\.?\s*', caseSensitive: false), 'Desa ');
    s = s.replaceAll(
        RegExp(r'\b(?:dsn|dusun)\b\.?\s*', caseSensitive: false), 'Dusun ');
    s = s.replaceAll(
        RegExp(r'\b(?:prov|provinsi|propinsi)\b\.?\s*', caseSensitive: false),
        'Provinsi ');
    s = s.replaceAll(
        RegExp(r'\b(?:komp|kompleks|komplek)\b\.?\s*', caseSensitive: false),
        'Komplek ');
    s = s.replaceAll(
        RegExp(r'\b(?:perum|perumahan)\b\.?\s*', caseSensitive: false),
        'Perumahan ');
    s = s.replaceAll(
        RegExp(r'\b(?:gd|gedung)\b\.?\s*', caseSensitive: false), 'Gedung ');
    s = s.replaceAll(
        RegExp(r'\b(?:gg|gang)\b\.?\s*', caseSensitive: false), 'Gang ');
    s = s.replaceAll(
        RegExp(r'\b(?:kp|kampung)\b\.?\s*', caseSensitive: false), 'Kampung ');
    s = s.replaceAll(RegExp(r'\brt\b', caseSensitive: false), 'RT');
    s = s.replaceAll(RegExp(r'\brw\b', caseSensitive: false), 'RW');
    s = s.replaceAll(RegExp(r'\bno\b', caseSensitive: false), 'No');
    s = s.replaceAll(RegExp(r'[()\[\]]'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Mencocokkan nama kota hasil OCR dengan daftar kota (toleran 1-2 huruf).
  String _fixCity(String raw) {
    return _matchKnown(raw, IndonesianPlaces.cities, whole: true) ?? raw;
  }

  /// Nama dari [names] yang cocok dengan [text]. Bila [whole] true, seluruh
  /// teks dibandingkan secara fuzzy; bila false, nama harus muncul utuh
  /// sebagai kata di dalam teks (atau teks itu sendiri mirip nama).
  String? _matchKnown(String text, List<String> names, {bool whole = false}) {
    final String t = _key(text);
    if (t.isEmpty) return null;
    String? best;
    for (final String name in names) {
      final String n = name.toLowerCase();
      if (!whole &&
          RegExp('(?:^|\\s)${RegExp.escape(n)}(?:\$|\\s)').hasMatch(t)) {
        if (best == null || n.length > best.length) best = name;
      }
    }
    if (best != null) return best;
    if (t.length < 5 || t.length > 24) return null;
    int bestDist = 99;
    for (final String name in names) {
      final String n = name.toLowerCase();
      if ((n.length - t.length).abs() > 2) continue;
      final int d = _levenshtein(t, n);
      final int allowed = n.length >= 8 ? 2 : (n.length >= 5 ? 2 : 1);
      if (d <= allowed && d < bestDist) {
        bestDist = d;
        best = name;
      }
    }
    return best;
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

  String _key(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _clean(String s) => s
      .replaceAll(RegExp(r'^[^A-Za-z0-9]+'), '')
      .replaceAll(RegExp(r'[^A-Za-z0-9.]+$'), '')
      .replaceAll(RegExp(r'\.$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static const Set<String> _keepUpper = <String>{
    'RT',
    'RW',
    'DKI',
    'DI',
    'II',
    'III',
    'IV'
  };

  String _titleCase(String s) =>
      s.split(' ').where((String w) => w.isNotEmpty).map((String w) {
        if (_keepUpper.contains(w.toUpperCase())) return w.toUpperCase();
        if (RegExp(r'\d').hasMatch(w)) return w.toUpperCase();
        return '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}';
      }).join(' ');
}
