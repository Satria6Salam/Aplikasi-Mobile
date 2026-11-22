import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'store_address_extractor.dart';

/// Galat saat menghubungi API geocoding (offline, batas waktu, server sibuk).
class GeocodingException implements Exception {
  const GeocodingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Kotak batas pencarian (derajat lintang/bujur).
class GeoBox {
  const GeoBox({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  /// Kotak selebar ±[deg] derajat di sekitar [center] (0,01° ≈ 1,1 km).
  factory GeoBox.around(LatLng center, double deg) => GeoBox(
        south: center.latitude - deg,
        west: center.longitude - deg,
        north: center.latitude + deg,
        east: center.longitude + deg,
      );

  final double south;
  final double west;
  final double north;
  final double east;
}

/// Satu hasil mentah dari API Nominatim.
class GeocodeCandidate {
  const GeocodeCandidate({
    required this.point,
    required this.displayName,
    required this.name,
    required this.category,
    required this.type,
    required this.addressType,
    required this.address,
    required this.importance,
  });

  final LatLng point;
  final String displayName;
  final String name;
  final String category;
  final String type;
  final String addressType;
  final Map<String, String> address;
  final double importance;

  String? get postcode => address['postcode'];

  factory GeocodeCandidate.fromJson(Map<String, Object?> json) {
    final Map<String, String> address = <String, String>{};
    final Object? raw = json['address'];
    if (raw is Map) {
      raw.forEach((Object? k, Object? v) {
        if (k is String && v != null) address[k] = v.toString();
      });
    }
    return GeocodeCandidate(
      point: LatLng(
        double.parse(json['lat'].toString()),
        double.parse(json['lon'].toString()),
      ),
      displayName: (json['display_name'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      category: (json['category'] ?? json['class'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      addressType: (json['addresstype'] ?? '').toString(),
      address: address,
      importance: double.tryParse('${json['importance'] ?? 0}') ?? 0,
    );
  }

  /// Ketelitian titik ini berdasarkan jenis objek peta.
  LocationPrecision get precision {
    if (category == 'shop' ||
        category == 'amenity' ||
        category == 'building' ||
        category == 'tourism' ||
        category == 'office' ||
        category == 'healthcare' ||
        addressType == 'shop' ||
        addressType == 'amenity' ||
        addressType == 'building' ||
        addressType == 'house') {
      return LocationPrecision.store;
    }
    if (category == 'highway' || addressType == 'road') {
      return LocationPrecision.street;
    }
    switch (addressType) {
      case 'village':
      case 'hamlet':
      case 'neighbourhood':
      case 'quarter':
      case 'suburb':
        return LocationPrecision.village;
      case 'city_district':
      case 'municipality':
      case 'district':
        return LocationPrecision.district;
      case 'postcode':
        return LocationPrecision.postalCode;
      default:
        return LocationPrecision.city;
    }
  }
}

/// Klien HTTP untuk API Nominatim (OpenStreetMap). Gratis tanpa API key,
/// dengan syarat: maksimal 1 permintaan per detik dan wajib User-Agent.
/// https://operations.osmfoundation.org/policies/nominatim/
class NominatimClient {
  NominatimClient({
    http.Client? client,
    this.baseUrl = 'nominatim.openstreetmap.org',
    this.minInterval = const Duration(milliseconds: 1100),
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  static const String userAgent = 'SmartReceipt/1.0 (aplikasi tugas kuliah)';

  final http.Client _client;
  final String baseUrl;
  final Duration minInterval;
  final Duration timeout;

  DateTime? _lastRequest;
  Future<void> _queue = Future<void>.value();

  /// Pencarian alamat/nama tempat (forward geocoding).
  Future<List<GeocodeCandidate>> search(
    String query, {
    GeoBox? viewbox,
    bool bounded = false,
    int limit = 5,
  }) async {
    final Map<String, String> params = <String, String>{
      'q': query,
      'format': 'jsonv2',
      'addressdetails': '1',
      'countrycodes': 'id',
      'accept-language': 'id',
      'limit': '$limit',
      if (viewbox != null)
        'viewbox': '${viewbox.west},${viewbox.north},'
            '${viewbox.east},${viewbox.south}',
      if (viewbox != null && bounded) 'bounded': '1',
    };
    final Object? body = await _get('/search', params);
    if (body is! List) return <GeocodeCandidate>[];
    return body
        .whereType<Map<String, Object?>>()
        .map(GeocodeCandidate.fromJson)
        .toList();
  }

  /// Koordinat -> alamat (reverse geocoding).
  Future<GeocodeCandidate?> reverse(LatLng point) async {
    final Object? body = await _get('/reverse', <String, String>{
      'lat': '${point.latitude}',
      'lon': '${point.longitude}',
      'format': 'jsonv2',
      'addressdetails': '1',
      'accept-language': 'id',
      'zoom': '18',
    });
    if (body is! Map<String, Object?> || body.containsKey('error')) {
      return null;
    }
    return GeocodeCandidate.fromJson(body);
  }

  /// Permintaan dijalankan berurutan dengan jeda minimal [minInterval].
  Future<Object?> _get(String path, Map<String, String> params) {
    final Completer<Object?> done = Completer<Object?>();
    _queue = _queue.then((_) async {
      try {
        final DateTime? last = _lastRequest;
        if (last != null) {
          final Duration wait = minInterval - DateTime.now().difference(last);
          if (!wait.isNegative) await Future<void>.delayed(wait);
        }
        _lastRequest = DateTime.now();
        final http.Response res = await _client.get(
          Uri.https(baseUrl, path, params),
          headers: <String, String>{'User-Agent': userAgent},
        ).timeout(timeout);
        if (res.statusCode == 429) {
          throw const GeocodingException(
              'Server peta sedang sibuk. Coba lagi sebentar lagi.');
        }
        if (res.statusCode != 200) {
          throw GeocodingException(
              'Server peta menolak permintaan (kode ${res.statusCode}).');
        }
        done.complete(jsonDecode(utf8.decode(res.bodyBytes)));
      } on GeocodingException catch (e) {
        done.completeError(e);
      } on TimeoutException {
        done.completeError(const GeocodingException(
            'Server peta tidak merespons. Periksa koneksi internet.'));
      } catch (_) {
        done.completeError(const GeocodingException(
            'Tidak dapat terhubung ke server peta. Periksa koneksi internet.'));
      }
    });
    return done.future;
  }

  void close() => _client.close();
}

/// Lokasi toko terpilih beserta tingkat keyakinannya.
class StoreLocation {
  const StoreLocation({
    required this.point,
    required this.displayName,
    required this.precision,
    required this.confidence,
    required this.source,
  });

  final LatLng point;

  /// Alamat menurut peta (dari API), untuk ditunjukkan ke pengguna.
  final String displayName;
  final LocationPrecision precision;

  /// 0..1. Di atas 0,7 dianggap akurat; di bawah 0,4 hanya perkiraan kasar.
  final double confidence;

  /// Lihat [LocationSource].
  final String source;

  /// Akurat = yakin DAN setidaknya setingkat jalan (bukan sekadar
  /// kecamatan/kota yang benar).
  bool get isAccurate =>
      confidence >= 0.7 && precision.index <= LocationPrecision.street.index;

  StoreLocation copyWith({
    LatLng? point,
    String? displayName,
    LocationPrecision? precision,
    double? confidence,
    String? source,
  }) {
    return StoreLocation(
      point: point ?? this.point,
      displayName: displayName ?? this.displayName,
      precision: precision ?? this.precision,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
    );
  }
}

/// Asal sebuah lokasi (disimpan di kolom location_source).
class LocationSource {
  LocationSource._();

  /// Dari alamat pada struk (geocoding).
  static const String receipt = 'receipt';

  /// Dari pencarian nama toko di sekitar posisi GPS.
  static const String nearby = 'nearby';

  /// Posisi GPS perangkat saat memindai.
  static const String gps = 'gps';

  /// Dipilih/digeser pengguna di peta.
  static const String manual = 'manual';

  /// Dari riwayat toko yang sama.
  static const String cache = 'cache';

  static String label(String source) => switch (source) {
        receipt => 'Alamat struk',
        nearby => 'Toko terdekat (GPS)',
        gps => 'Posisi GPS',
        manual => 'Diatur manual',
        cache => 'Riwayat toko',
        _ => source,
      };
}

/// Mencari titik toko dari alamat struk dengan beberapa kueri bertingkat,
/// lalu memilih kandidat terbaik dengan mencocokkan setiap komponen alamat
/// (jalan, kelurahan, kecamatan, kota, kode pos, nama toko) dan jarak ke
/// posisi pengguna bila tersedia.
class StoreLocator {
  StoreLocator({required NominatimClient client, this.maxRequests = 7})
      : _client = client;

  final NominatimClient _client;
  final int maxRequests;

  static const Distance _distance = Distance();

  /// [nearby] hanya diisi bila posisi GPS dapat dipercaya mewakili toko
  /// (mis. struk difoto langsung di kasir pada hari transaksi).
  Future<StoreLocation?> locate({
    required StoreAddress address,
    String? merchantName,
    LatLng? nearby,
  }) async {
    final String merchant = (merchantName ?? '').trim();
    StoreLocation? best;
    int requests = 0;
    GeocodingException? lastError;

    void consider(List<GeocodeCandidate> found, LocationPrecision expected,
        String source) {
      for (final GeocodeCandidate c in found) {
        final StoreLocation scored =
            _score(c, address, merchant, nearby, expected, source);
        if (best == null || scored.confidence > best!.confidence) {
          best = scored;
        }
      }
    }

    bool goodEnough() {
      final StoreLocation? b = best;
      return b != null &&
          b.confidence >= 0.75 &&
          b.precision.index <= LocationPrecision.street.index;
    }

    // 1. Nama toko di sekitar GPS (paling tepat untuk jaringan minimarket).
    if (nearby != null && merchant.isNotEmpty) {
      try {
        requests++;
        consider(
          await _client.search(merchant,
              viewbox: _box(nearby, 0.02), bounded: true, limit: 8),
          LocationPrecision.store,
          LocationSource.nearby,
        );
      } on GeocodingException catch (e) {
        lastError = e;
      }
    }

    // 2. Alamat struk, dari paling rinci ke paling kasar.
    if (address.isNotEmpty) {
      for (final AddressQuery q in address.geocodeQueries(merchant)) {
        if (goodEnough() || requests >= maxRequests) break;
        // Kueri yang lebih kasar dari hasil terbaik tidak akan menang.
        final StoreLocation? b = best;
        if (b != null &&
            b.confidence >= 0.5 &&
            q.precision.index > b.precision.index) {
          break;
        }
        try {
          requests++;
          consider(
            await _client.search(q.text,
                viewbox: nearby == null ? null : _box(nearby, 0.3)),
            q.precision,
            LocationSource.receipt,
          );
        } on GeocodingException catch (e) {
          lastError = e;
          if (best == null && requests == 1) rethrow;
        }
      }
    }

    // 3. Sudah menemukan jalan/kelurahan tetapi belum tokonya: cari nama toko
    //    di sekitar titik itu (toko di OSM biasanya bernama "Indomaret" saja).
    final StoreLocation? anchor = best;
    if (anchor != null &&
        merchant.isNotEmpty &&
        requests < maxRequests &&
        (anchor.precision == LocationPrecision.street ||
            anchor.precision == LocationPrecision.village)) {
      try {
        requests++;
        consider(
          await _client.search(merchant,
              viewbox: _box(anchor.point, 0.012), bounded: true, limit: 10),
          LocationPrecision.store,
          LocationSource.receipt,
        );
      } on GeocodingException {
        // Titik jalan/kelurahan yang sudah ada tetap dipakai.
      }
    }

    // 4. Tidak ada alamat yang cocok: pakai posisi GPS sebagai perkiraan.
    if (best == null && nearby != null) {
      try {
        final GeocodeCandidate? here = await _client.reverse(nearby);
        best = StoreLocation(
          point: nearby,
          displayName: here?.displayName ?? 'Posisi Anda saat memindai',
          precision: LocationPrecision.store,
          confidence: 0.55,
          source: LocationSource.gps,
        );
      } on GeocodingException {
        best = StoreLocation(
          point: nearby,
          displayName: 'Posisi Anda saat memindai',
          precision: LocationPrecision.store,
          confidence: 0.5,
          source: LocationSource.gps,
        );
      }
    }

    if (best == null && lastError != null) throw lastError;
    return best;
  }

  /// Alamat menurut peta untuk titik pilihan pengguna.
  Future<String?> describe(LatLng point) async {
    final GeocodeCandidate? c = await _client.reverse(point);
    return c?.displayName;
  }

  GeoBox _box(LatLng center, double deg) => GeoBox.around(center, deg);

  StoreLocation _score(
    GeocodeCandidate c,
    StoreAddress a,
    String merchant,
    LatLng? nearby,
    LocationPrecision expected,
    String source,
  ) {
    final String hay = _norm(<String>[
      c.name,
      c.displayName,
      ...c.address.values,
    ].join(' '));
    // Jalan dicocokkan hanya dengan nama jalan/objek, bukan alamat lengkap:
    // "Jalan Masjid, ..., Urek - Urek" bukan "Jalan Raya Urek Urek".
    final String roadText = _norm('${c.address['road'] ?? ''} '
        '${c.category == 'highway' ? c.name : ''}');
    final String localText = _norm('$roadText ${c.name} '
        '${c.address['village'] ?? ''} ${c.address['hamlet'] ?? ''} '
        '${c.address['suburb'] ?? ''} ${c.address['neighbourhood'] ?? ''} '
        '${c.address['quarter'] ?? ''}');

    bool near(String? s, String text) =>
        s != null && _tokenMatch(s, text) >= 0.5;
    final bool nameOk =
        merchant.isNotEmpty && _tokenMatch(merchant, _norm(c.name)) >= 0.5;

    // ---- 1. Ketelitian kandidat.
    LocationPrecision precision = c.precision;
    if (precision == LocationPrecision.store &&
        merchant.isNotEmpty &&
        !nameOk) {
      // Ada bangunan/toko, tetapi bukan toko ini: hanya patokan jalan.
      precision = a.street != null
          ? LocationPrecision.street
          : LocationPrecision.village;
    }
    // Toko senama di jalan/kelurahan lain (mis. Indomaret cabang lain di
    // kecamatan yang sama) BUKAN toko pada struk.
    if (precision == LocationPrecision.store &&
        (a.street != null || a.village != null || a.branchName != null) &&
        !near(a.street, localText) &&
        !near(a.village, localText) &&
        !near(a.branchName, localText)) {
      precision = near(a.district, hay)
          ? LocationPrecision.district
          : LocationPrecision.city;
    }

    // ---- 2. Kecocokan teks, hanya komponen yang masuk akal untuk
    //         ketelitian itu (kelurahan tidak dinilai dari nama jalan).
    double got = 0;
    double weight = 0;
    void part(String? ours, double w, double Function(String) matcher) {
      if (ours == null || ours.trim().isEmpty) return;
      weight += w;
      got += w * matcher(ours);
    }

    double village(String s) =>
        _tokenMatch(s, localText.isEmpty ? hay : localText);
    double anywhere(String s) => _tokenMatch(s, hay);
    double postal(String s) {
      final String? pc = c.postcode?.trim();
      if (pc == null || pc.isEmpty) return 0.3; // Peta sering tanpa kode pos.
      if (pc == s) return 1;
      if (pc.length >= 4 && pc.substring(0, 4) == s.substring(0, 4)) return 0.7;
      if (pc.length >= 3 && pc.substring(0, 3) == s.substring(0, 3)) return 0.4;
      return 0;
    }

    final String? villageOurs = a.village ?? a.branchName;
    switch (precision) {
      case LocationPrecision.store:
        part(a.street, 0.3, (String s) => _tokenMatch(s, roadText));
        part(villageOurs, 0.1, village);
        part(a.district, 0.15, anywhere);
        part(a.cityName, 0.15, anywhere);
        part(a.postalCode, 0.1, postal);
        part(merchant, 0.3, (String s) => _tokenMatch(s, _norm(c.name)));
      case LocationPrecision.street:
        part(a.street, 0.4, (String s) => _tokenMatch(s, roadText));
        part(villageOurs, 0.1, village);
        part(a.district, 0.2, anywhere);
        part(a.cityName, 0.2, anywhere);
        part(a.postalCode, 0.1, postal);
      case LocationPrecision.village:
        part(villageOurs, 0.4, village);
        part(a.district, 0.25, anywhere);
        part(a.cityName, 0.2, anywhere);
        part(a.postalCode, 0.15, postal);
      case LocationPrecision.district:
        part(a.district, 0.5, anywhere);
        part(a.cityName, 0.3, anywhere);
        part(a.postalCode, 0.2, postal);
      case LocationPrecision.postalCode:
        part(a.postalCode, 0.7, postal);
        part(a.cityName, 0.3, anywhere);
      case LocationPrecision.city:
        part(a.cityName, 1, anywhere);
    }
    double text = weight == 0 ? 0.5 : got / weight;

    // Hanya nama toko (pencarian di sekitar GPS tanpa alamat pembanding).
    if (a.isEmpty && source == LocationSource.nearby) {
      text = _tokenMatch(merchant, _norm(c.name));
    }

    // Kecamatan jelas berbeda: hampir pasti tempat lain yang kebetulan senama.
    final String? candDistrict = c.address['city_district'] ??
        c.address['municipality'] ??
        c.address['district'];
    if (a.district != null && candDistrict != null && !near(a.district, hay)) {
      text *= 0.5;
    }

    // ---- 3. Kedekatan dengan GPS.
    double gpsBonus = 0;
    if (nearby != null) {
      final double km = _distance.as(LengthUnit.Meter, nearby, c.point) / 1000;
      if (km < 0.3) {
        gpsBonus = 0.2;
      } else if (km < 1) {
        gpsBonus = 0.12;
      } else if (km < 3) {
        gpsBonus = 0.05;
      } else if (km > 30) {
        gpsBonus = -0.3;
      }
    }

    // ---- 4. Batas atas keyakinan menurut ketelitian.
    final double cap = switch (precision) {
      LocationPrecision.store => 1.0,
      LocationPrecision.street => 0.9,
      LocationPrecision.village => 0.72,
      LocationPrecision.district => 0.55,
      LocationPrecision.postalCode => 0.45,
      LocationPrecision.city => 0.3,
    };

    final double confidence =
        math.max(0, math.min(1, text * cap + gpsBonus)).toDouble();
    return StoreLocation(
      point: c.point,
      displayName: c.displayName,
      precision: precision,
      confidence: double.parse(confidence.toStringAsFixed(3)),
      source: source,
    );
  }

  static const Set<String> _stopWords = <String>{
    'jalan',
    'jl',
    'kecamatan',
    'kabupaten',
    'kota',
    'kelurahan',
    'desa',
    'dusun',
    'provinsi',
    'raya',
    'no',
    'rt',
    'rw',
    'toko',
    'indonesia',
  };

  String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Porsi kata pada [ours] yang ditemukan di [hay] (toleran salah ketik 1 huruf).
  double _tokenMatch(String ours, String hay) {
    final List<String> tokens = _norm(ours)
        .split(' ')
        .where((String t) => t.length >= 2 && !_stopWords.contains(t))
        .toList();
    if (tokens.isEmpty) {
      // Hanya kata umum (mis. "Jalan Raya"): cocokkan apa adanya.
      return hay.contains(_norm(ours)) ? 1 : 0;
    }
    final List<String> words = hay.split(' ');
    int hit = 0;
    for (final String t in tokens) {
      if (words.contains(t) ||
          (t.length >= 5 &&
              words.any((String w) =>
                  (w.length - t.length).abs() <= 1 && _oneEdit(w, t)))) {
        hit++;
      }
    }
    return hit / tokens.length;
  }

  bool _oneEdit(String a, String b) {
    if (a == b) return true;
    if (a.length == b.length) {
      int diff = 0;
      for (int i = 0; i < a.length; i++) {
        if (a[i] != b[i] && ++diff > 1) return false;
      }
      return true;
    }
    final String s = a.length < b.length ? a : b;
    final String l = a.length < b.length ? b : a;
    int i = 0;
    int j = 0;
    bool skipped = false;
    while (i < s.length && j < l.length) {
      if (s[i] == l[j]) {
        i++;
        j++;
      } else {
        if (skipped) return false;
        skipped = true;
        j++;
      }
    }
    return true;
  }
}
