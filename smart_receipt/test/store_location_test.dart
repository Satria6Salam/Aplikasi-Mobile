import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:smart_receipt/data/models/transaction_model.dart';
import 'package:smart_receipt/services/geocoding_service.dart';
import 'package:smart_receipt/services/ml_service.dart';
import 'package:smart_receipt/services/parsing_service.dart';
import 'package:smart_receipt/services/store_address_extractor.dart';
import 'package:smart_receipt/services/store_location_service.dart';
import 'package:smart_receipt/viewmodels/auth_viewmodel.dart';
import 'package:smart_receipt/viewmodels/scan_viewmodel.dart';
import 'package:smart_receipt/viewmodels/store_map_viewmodel.dart';

import 'viewmodels_test.dart'
    show
        FakeCategoryRepository,
        FakeImageFormatService,
        FakeImagePickerService,
        FakeImageStorageService,
        FakeOcrService,
        FakeTransactionRepository,
        buildLoggedInAuth,
        ocrOf;

// ------------------------------------------------------------ data tiruan

Map<String, Object?> place({
  required double lat,
  required double lon,
  required String display,
  String name = '',
  String category = 'highway',
  String type = 'residential',
  String addressType = 'road',
  Map<String, String> address = const <String, String>{},
}) =>
    <String, Object?>{
      'lat': '$lat',
      'lon': '$lon',
      'display_name': display,
      'name': name,
      'category': category,
      'type': type,
      'addresstype': addressType,
      'importance': 0.3,
      'address': address,
    };

/// Toko Indomaret Urek Urek yang sebenarnya.
final Map<String, Object?> indomaretUrek = place(
  lat: -8.1781,
  lon: 112.6355,
  name: 'Indomaret Urek Urek',
  category: 'shop',
  type: 'convenience',
  addressType: 'shop',
  display:
      'Indomaret Urek Urek, Jalan Raya Urek Urek, Urek Urek, Gondanglegi, Kabupaten Malang, Jawa Timur, 65174, Indonesia',
  address: <String, String>{
    'shop': 'Indomaret Urek Urek',
    'road': 'Jalan Raya Urek Urek',
    'village': 'Urek Urek',
    'city_district': 'Gondanglegi',
    'county': 'Kabupaten Malang',
    'state': 'Jawa Timur',
    'postcode': '65174',
  },
);

/// Indomaret lain dengan nama mirip tetapi di kota berbeda.
final Map<String, Object?> indomaretJakarta = place(
  lat: -6.1100,
  lon: 106.7400,
  name: 'Indomaret Boulevard',
  category: 'shop',
  type: 'convenience',
  addressType: 'shop',
  display:
      'Indomaret Boulevard, Pantai Indah Kapuk, Jakarta Utara, DKI Jakarta, 14470, Indonesia',
  address: <String, String>{
    'road': 'Jalan Pantai Indah Kapuk Boulevard',
    'city': 'Jakarta Utara',
    'postcode': '14470',
  },
);

final Map<String, Object?> roadUrek = place(
  lat: -8.1790,
  lon: 112.6340,
  display:
      'Jalan Raya Urek Urek, Urek Urek, Gondanglegi, Kabupaten Malang, Jawa Timur, Indonesia',
  address: <String, String>{
    'road': 'Jalan Raya Urek Urek',
    'village': 'Urek Urek',
    'city_district': 'Gondanglegi',
    'county': 'Kabupaten Malang',
  },
);

/// Klien Nominatim tiruan: setiap kueri dijawab oleh [responder].
NominatimClient fakeClient(
  List<Map<String, Object?>> Function(Uri uri) responder, {
  List<Uri>? log,
  int status = 200,
}) {
  return NominatimClient(
    minInterval: Duration.zero,
    client: MockClient((http.Request req) async {
      log?.add(req.url);
      expect(req.headers['User-Agent'], NominatimClient.userAgent);
      if (status != 200) return http.Response('', status);
      final Object body = req.url.path == '/reverse'
          ? (responder(req.url).isEmpty
              ? <String, Object?>{'error': 'Unable to geocode'}
              : responder(req.url).first)
          : responder(req.url);
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
          headers: <String, String>{'content-type': 'application/json'});
    }),
  );
}

const String indomaretReceipt = 'PT INDOMARCO PFISMATAMA\n'
    '(GEDUNG MENARA Sndsmael\n'
    'INDOMARET BOULEVARD\n'
    'PANTAINDAH KAPUK\n'
    'JAKARTA UTARA\n'
    'NPVWP 00 i337994 6-092 000\n'
    'UREK UREK\n'
    'JL. RAYA UREK UREK NO., UREK UREK\n'
    'KEC GONDANGLEGI, KARUPATEN HALAG, 65174\n'
    '13.11.26-20:51/4.6.0/TQJ3-307201/AMIN /01\n'
    'AMEL OPT PURPLE 16S 1 28000 28,000\n'
    'TOTAL BELANJA: 28,000';

StoreAddress indomaretAddress() => const StoreAddressExtractor()
    .extract(indomaretReceipt, merchantName: 'Indomaret');

// ------------------------------------------------------- layanan tiruan

class FakeLocationService extends StoreLocationService {
  FakeLocationService({
    this.result,
    this.error,
    this.position,
  }) : super(
          locator: StoreLocator(client: fakeClient((_) => const [])),
        );

  StoreLocation? result;
  GeocodingException? error;
  DevicePosition? position;

  final List<StoreAddress> lookedUp = <StoreAddress>[];
  final List<bool> gpsFlags = <bool>[];
  final List<String?> cacheKeys = <String?>[];
  final List<StoreLocation> remembered = <StoreLocation>[];

  @override
  Future<StoreLocation?> lookup({
    required int userId,
    required String merchantName,
    required StoreAddress address,
    String? cacheAddress,
    bool useGps = false,
  }) async {
    lookedUp.add(address);
    gpsFlags.add(useGps);
    cacheKeys.add(cacheAddress);
    final GeocodingException? e = error;
    if (e != null) throw e;
    return result;
  }

  @override
  Future<DeviceLocationResult> currentPosition() async {
    final DevicePosition? p = position;
    return p == null
        ? const DeviceLocationResult(LocationAccess.denied)
        : DeviceLocationResult(LocationAccess.granted, p);
  }

  @override
  Future<String?> describe(LatLng point) async =>
      'Jalan Contoh, Gondanglegi, Kabupaten Malang, Jawa Timur, Indonesia';

  @override
  Future<void> remember({
    required int userId,
    required String merchantName,
    required String? address,
    required StoreLocation location,
  }) async {
    remembered.add(location);
  }
}

Future<void> settle() async {
  for (int i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<ScanViewModel> scanWithLocation(
  FakeLocationService location,
  FakeTransactionRepository repo, {
  String receipt = indomaretReceipt,
  ScanSource source = ScanSource.gallery,
}) async {
  final AuthViewModel auth = await buildLoggedInAuth();
  final MlService ml = MlService();
  await ml.initialize();
  final ScanViewModel scan = ScanViewModel(
    authViewModel: auth,
    ocrService: FakeOcrService(result: ocrOf(receipt)),
    parsingService: const ParsingService(),
    mlService: ml,
    categoryRepository: FakeCategoryRepository(),
    transactionRepository: repo,
    imageStorageService: FakeImageStorageService(),
    imageFormatService: FakeImageFormatService(),
    imagePickerService: FakeImagePickerService(),
    storeLocationService: location,
  );
  await scan.processImage(imagePath: '/tmp/struk.jpg', source: source);
  await settle();
  return scan;
}

// ==================================================================== tes

void main() {
  group('StoreLocator (API Nominatim)', () {
    test('memilih cabang yang alamatnya cocok, bukan toko senama di kota lain',
        () async {
      final List<Uri> log = <Uri>[];
      final StoreLocator locator = StoreLocator(
        client: fakeClient(
          (Uri uri) => <Map<String, Object?>>[indomaretJakarta, indomaretUrek],
          log: log,
        ),
      );

      final StoreLocation? found = await locator.locate(
        address: indomaretAddress(),
        merchantName: 'Indomaret',
      );

      expect(found, isNotNull);
      expect(found!.point.latitude, closeTo(-8.1781, 1e-6));
      expect(found.precision, LocationPrecision.store);
      expect(found.isAccurate, isTrue);
      expect(found.source, LocationSource.receipt);
      // Hasil sudah akurat pada kueri pertama: tidak perlu kueri lain.
      expect(log, hasLength(1));
      expect(log.first.queryParameters['q'],
          'Indomaret Urek Urek, Kabupaten Malang');
      expect(log.first.queryParameters['countrycodes'], 'id');
    });

    test('turun ke kueri jalan bila toko tidak ada di peta', () async {
      final List<Uri> log = <Uri>[];
      final StoreLocator locator = StoreLocator(
        client: fakeClient(
          (Uri uri) => uri.queryParameters['q']!.startsWith('Indomaret')
              ? <Map<String, Object?>>[]
              : <Map<String, Object?>>[roadUrek],
          log: log,
        ),
      );

      final StoreLocation? found = await locator.locate(
        address: indomaretAddress(),
        merchantName: 'Indomaret',
      );

      expect(found!.precision, LocationPrecision.street);
      expect(found.confidence, greaterThan(0.6));
      expect(log.length, greaterThanOrEqualTo(2));
    });

    test('Indomaret cabang lain di kecamatan yang sama tidak dianggap tokonya',
        () async {
      // Meniru jawaban Nominatim sungguhan untuk struk Indomaret Urek Urek.
      final Map<String, Object?> trunojoyo = place(
        lat: -8.1614,
        lon: 112.6016,
        name: 'Indomaret',
        category: 'shop',
        type: 'convenience',
        addressType: 'shop',
        display:
            'Indomaret, Jalan Trunojoyo, Penjalinan, Gondanglegi, Sukosari, Kabupaten Malang, Jawa Timur, 65174, Indonesia',
        address: <String, String>{
          'road': 'Jalan Trunojoyo',
          'hamlet': 'Penjalinan',
          'village': 'Sukosari',
          'city_district': 'Gondanglegi',
          'county': 'Kabupaten Malang',
          'postcode': '65174',
        },
      );
      final Map<String, Object?> hamlet = place(
        lat: -8.1850,
        lon: 112.6420,
        category: 'place',
        type: 'hamlet',
        addressType: 'hamlet',
        display:
            'Urek-Urekbaran, Gondanglegi, Urek - Urek, Kabupaten Malang, Jawa Timur, 65171, Indonesia',
        address: <String, String>{
          'hamlet': 'Urek-Urekbaran',
          'village': 'Urek - Urek',
          'city_district': 'Gondanglegi',
          'county': 'Kabupaten Malang',
          'postcode': '65171',
        },
      );
      final StoreLocator locator = StoreLocator(
        client: fakeClient((Uri uri) {
          final String q = uri.queryParameters['q'] ?? '';
          if (q == 'Indomaret Gondanglegi, Kabupaten Malang' ||
              q == 'Indomaret') {
            return <Map<String, Object?>>[trunojoyo];
          }
          if (q.startsWith('Urek Urek')) return <Map<String, Object?>>[hamlet];
          return <Map<String, Object?>>[];
        }),
      );

      final StoreLocation? found = await locator.locate(
        address: indomaretAddress(),
        merchantName: 'Indomaret',
      );

      expect(found!.point.latitude, closeTo(-8.1850, 1e-6),
          reason: 'titik kelurahan Urek Urek lebih tepat daripada toko lain');
      expect(found.precision, LocationPrecision.village);
      expect(found.isAccurate, isFalse);
    });

    test('hanya cocok di tingkat kota dianggap perkiraan kasar', () async {
      final StoreLocator locator = StoreLocator(
        client: fakeClient(
          (Uri uri) => <Map<String, Object?>>[
            place(
              lat: -8.0,
              lon: 112.6,
              display: 'Kabupaten Malang, Jawa Timur, Indonesia',
              category: 'boundary',
              type: 'administrative',
              addressType: 'county',
              address: <String, String>{'county': 'Kabupaten Malang'},
            ),
          ],
        ),
      );

      final StoreLocation? found = await locator.locate(
        address: indomaretAddress(),
        merchantName: 'Indomaret',
      );

      expect(found!.precision, LocationPrecision.city);
      expect(found.isAccurate, isFalse);
      expect(found.confidence, lessThan(0.4));
    });

    test('GPS di dekat toko menyaring kandidat senama', () async {
      final List<Uri> log = <Uri>[];
      final StoreLocator locator = StoreLocator(
        client: fakeClient(
          (Uri uri) => <Map<String, Object?>>[indomaretJakarta, indomaretUrek],
          log: log,
        ),
      );

      final StoreLocation? found = await locator.locate(
        address: StoreAddress.empty,
        merchantName: 'Indomaret',
        nearby: const LatLng(-8.1785, 112.6350),
      );

      expect(found!.point.latitude, closeTo(-8.1781, 1e-6));
      expect(found.source, LocationSource.nearby);
      expect(log.first.queryParameters['bounded'], '1');
      expect(log.first.queryParameters['viewbox'], isNotNull);
    });

    test('tanpa hasil sama sekali tetapi ada GPS: pakai posisi GPS', () async {
      final StoreLocator locator = StoreLocator(
        client: fakeClient((Uri uri) => <Map<String, Object?>>[]),
      );

      final StoreLocation? found = await locator.locate(
        address: StoreAddress.empty,
        merchantName: 'Warung Bu Siti',
        nearby: const LatLng(-7.0, 110.4),
      );

      expect(found!.source, LocationSource.gps);
      expect(found.point, const LatLng(-7.0, 110.4));
    });

    test('server sibuk (429) menjadi pesan yang jelas', () async {
      final StoreLocator locator = StoreLocator(
        client: fakeClient((_) => const [], status: 429),
      );

      expect(
        () => locator.locate(
            address: indomaretAddress(), merchantName: 'Indomaret'),
        throwsA(isA<GeocodingException>().having(
            (GeocodingException e) => e.message, 'message', contains('sibuk'))),
      );
    });

    test('permintaan dijeda minimal sesuai batas Nominatim', () async {
      final List<DateTime> times = <DateTime>[];
      final NominatimClient client = NominatimClient(
        minInterval: const Duration(milliseconds: 120),
        client: MockClient((http.Request req) async {
          times.add(DateTime.now());
          return http.Response('[]', 200);
        }),
      );

      await Future.wait(<Future<Object?>>[
        client.search('a'),
        client.search('b'),
        client.search('c'),
      ]);

      expect(times, hasLength(3));
      for (int i = 1; i < times.length; i++) {
        expect(times[i].difference(times[i - 1]).inMilliseconds,
            greaterThanOrEqualTo(110));
      }
    });
  });

  group('ScanViewModel - lokasi toko', () {
    final StoreLocation urek = StoreLocation(
      point: const LatLng(-8.1781, 112.6355),
      displayName: 'Indomaret Urek Urek, Gondanglegi, Kabupaten Malang',
      precision: LocationPrecision.store,
      confidence: 0.9,
      source: LocationSource.receipt,
    );

    test('alamat struk terisi dan lokasi dicari otomatis', () async {
      final FakeLocationService location = FakeLocationService(result: urek);
      final ScanViewModel scan =
          await scanWithLocation(location, FakeTransactionRepository());

      final ScanDraft draft = scan.draft!;
      expect(draft.storeBranch, 'Urek Urek');
      expect(draft.storeAddress, contains('Kecamatan Gondanglegi'));
      expect(draft.storeAddress, contains('Kabupaten Malang 65174'));
      expect(draft.locationStatus, LocationLookupStatus.found);
      expect(draft.location, same(urek));
      expect(scan.locationSearchName, 'Indomaret Urek Urek');
      // Dari galeri: GPS tidak dipakai karena belum tentu difoto di toko.
      expect(location.gpsFlags.single, isFalse);
      expect(location.cacheKeys.single, isNotNull);
    });

    test('foto kamera hari ini memakai GPS sebagai patokan', () async {
      final FakeLocationService location = FakeLocationService(result: urek);
      final String today = () {
        final DateTime n = DateTime.now();
        String two(int v) => v.toString().padLeft(2, '0');
        return '${two(n.day)}/${two(n.month)}/${n.year}';
      }();
      await scanWithLocation(
        location,
        FakeTransactionRepository(),
        receipt: 'INDOMARET\nJl. Raya Malang\n$today\nRoti 12.000\nTOTAL 12.000',
        source: ScanSource.camera,
      );

      expect(location.gpsFlags.single, isTrue);
    });

    test('lokasi ikut tersimpan dan diingat untuk struk berikutnya', () async {
      final FakeLocationService location = FakeLocationService(result: urek);
      final FakeTransactionRepository repo = FakeTransactionRepository();
      final ScanViewModel scan = await scanWithLocation(location, repo);

      expect(await scan.saveTransaction(), isTrue);

      final TransactionModel saved = repo.stored.single;
      expect(saved.storeBranch, 'Urek Urek');
      expect(saved.storeAddress, contains('Gondanglegi'));
      expect(saved.latitude, closeTo(-8.1781, 1e-6));
      expect(saved.longitude, closeTo(112.6355, 1e-6));
      expect(saved.locationPrecision, 'store');
      expect(saved.locationSource, LocationSource.receipt);
      expect(location.remembered, hasLength(1));
    });

    test('alamat disunting lalu dicari ulang memakai alamat baru', () async {
      final FakeLocationService location = FakeLocationService(result: null);
      final ScanViewModel scan =
          await scanWithLocation(location, FakeTransactionRepository());
      expect(scan.draft!.locationStatus, LocationLookupStatus.notFound);

      location.result = urek;
      scan.updateStoreAddress('Jl. Raya Urek Urek, Kec. Gondanglegi, Kab. Malang');
      await scan.searchLocation();

      expect(location.lookedUp.last.district, 'Gondanglegi');
      expect(location.lookedUp.last.city, 'Kabupaten Malang');
      expect(location.cacheKeys.last, isNull,
          reason: 'alamat suntingan tidak memakai cache');
      expect(scan.draft!.location, same(urek));
    });

    test('titik manual dari peta dan keterangan alamat dari reverse geocoding',
        () async {
      final FakeLocationService location = FakeLocationService(result: null);
      final ScanViewModel scan = await scanWithLocation(
        location,
        FakeTransactionRepository(),
        receipt: 'KEDAI KOPI\n01/10/2026\nKopi Susu 18.000\nTotal 18.000',
      );
      expect(scan.draft!.locationStatus, LocationLookupStatus.notFound);
      expect(location.lookedUp, isEmpty,
          reason: 'tanpa alamat dan tanpa GPS tidak perlu memanggil API');

      await scan.setManualLocation(const LatLng(-8.0, 112.6));

      final ScanDraft draft = scan.draft!;
      expect(draft.location!.source, LocationSource.manual);
      expect(draft.location!.isAccurate, isTrue);
      expect(draft.location!.displayName, contains('Gondanglegi'));
      expect(draft.storeAddress,
          'Jalan Contoh, Gondanglegi, Kabupaten Malang, Jawa Timur');
    });

    test('galat jaringan ditampilkan tanpa menggagalkan pratinjau', () async {
      final FakeLocationService location = FakeLocationService(
        error: const GeocodingException('Tidak dapat terhubung ke server peta.'),
      );
      final ScanViewModel scan =
          await scanWithLocation(location, FakeTransactionRepository());

      expect(scan.status, ScanStatus.ready);
      expect(scan.draft!.locationStatus, LocationLookupStatus.failed);
      expect(scan.draft!.locationMessage, contains('server peta'));
      expect(await scan.saveTransaction(), isTrue,
          reason: 'transaksi tetap bisa disimpan tanpa lokasi');
    });

    test('izin GPS ditolak memberi pesan dan lokasi lama tetap', () async {
      final FakeLocationService location = FakeLocationService(result: urek);
      final ScanViewModel scan =
          await scanWithLocation(location, FakeTransactionRepository());

      await scan.useCurrentLocation();

      expect(scan.draft!.location, same(urek));
      expect(scan.draft!.locationMessage, 'Izin lokasi ditolak.');
    });
  });

  group('StoreMapViewModel', () {
    TransactionModel tx(String merchant, double lat, double lng, double total) {
      final DateTime now = DateTime(2026, 11, 1);
      return TransactionModel(
        userId: 1,
        merchantName: merchant,
        transactionDate: now,
        totalAmount: total,
        categoryId: 1,
        createdAt: now,
        updatedAt: now,
        latitude: lat,
        longitude: lng,
      );
    }

    test('transaksi di toko yang sama digabung, cabang berbeda dipisah', () {
      final List<StorePlace> places = StoreMapViewModel.group(<TransactionModel>[
        tx('Indomaret', -8.17810, 112.63550, 28000),
        tx('Indomaret', -8.17812, 112.63555, 12000), // ±6 m: toko yang sama
        tx('Indomaret', -8.20000, 112.60000, 5000), // cabang lain
        tx('Alfamart', -8.17810, 112.63550, 50000),
      ]);

      expect(places, hasLength(3));
      expect(places.first.merchantName, 'Alfamart');
      final StorePlace urek = places
          .firstWhere((StorePlace p) => p.merchantName == 'Indomaret' && p.visits == 2);
      expect(urek.totalSpent, 40000);
    });
  });
}
