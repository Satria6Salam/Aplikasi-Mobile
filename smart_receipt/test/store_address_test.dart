import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/services/parsing_service.dart';
import 'package:smart_receipt/services/store_address_extractor.dart';

void main() {
  const StoreAddressExtractor extractor = StoreAddressExtractor();

  group('StoreAddressExtractor', () {
    test('struk Indomaret: alamat cabang dipilih, bukan alamat kantor pusat',
        () {
      const String raw = 'PT INDOMARCO PFISMATAMA\n'
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

      final StoreAddress a = extractor.extract(raw, merchantName: 'Indomaret');

      expect(a.branchName, 'Urek Urek');
      expect(a.street, 'Jalan Raya Urek Urek');
      expect(a.houseNumber, isNull);
      expect(a.village, 'Urek Urek');
      expect(a.district, 'Gondanglegi');
      expect(a.city, 'Kabupaten Malang', reason: 'HALAG dikoreksi ke Malang');
      expect(a.postalCode, '65174');
      expect(a.fullAddress,
          'Jalan Raya Urek Urek, Urek Urek, Kecamatan Gondanglegi, Kabupaten Malang 65174');
      expect(a.rawLines.any((String l) => l.contains('JAKARTA')), isFalse);
    });

    test('jalan bernomor dan baris telepon', () {
      const String raw = 'sURYA ELEKTRONIK\n'
          'Jl. Veteran Utara No.248B\n'
          'Telp. 0411 3628529\n'
          'Sabtu, 16 November 2019\n'
          'PPG\n'
          '500.000 X1 500.000';

      final StoreAddress a = extractor.extract(raw, merchantName: 'Surya Elektronik');

      expect(a.street, 'Jalan Veteran Utara');
      expect(a.houseNumber, '248B');
      expect(a.phone, '0411 3628529');
      expect(a.branchName, isNull);
    });

    test('kelurahan, kota, dan kode pos dalam satu baris', () {
      const String raw = 'TOKO SUMBER REJEKI\n'
          'Kel. Sukamaju Kota Bandung 40123\n'
          'Gula Pasir 1kg 15.000\n'
          'TOTAL 15.000';

      final StoreAddress a =
          extractor.extract(raw, merchantName: 'Toko Sumber Rejeki');

      expect(a.village, 'Sukamaju');
      expect(a.city, 'Kota Bandung');
      expect(a.postalCode, '40123');
      expect(a.branchName, isNull);
    });

    test('alamat dua baris dengan RT/RW, kecamatan, dan provinsi', () {
      const String raw = 'WARUNG BU SITI\n'
          'Jln. Kaliurang Km 5 No 12 RT 03/RW 11\n'
          'Kec. Depok, Kab. Sleman\n'
          'DI Yogyakarta 55281\n'
          '12/10/2026\n'
          'Nasi Gudeg 15.000\n'
          'TOTAL 15.000';

      final StoreAddress a = extractor.extract(raw, merchantName: 'Warung Bu Siti');

      expect(a.street, 'Jalan Kaliurang Km 5');
      expect(a.houseNumber, '12');
      expect(a.rtRw, 'RT 03/RW 11');
      expect(a.district, 'Depok');
      expect(a.city, 'Kabupaten Sleman');
      expect(a.province, 'DI Yogyakarta');
      expect(a.postalCode, '55281');
    });

    test('OCR membaca "Jl" sebagai "JI" dan nama kota tanpa kata kunci', () {
      const String raw = 'APOTEK SEHAT\n'
          'JI. Diponegoro 45\n'
          'Surabaya\n'
          '01/10/2026\n'
          'Paracetamol 8.000';

      final StoreAddress a = extractor.extract(raw, merchantName: 'Apotek Sehat');

      expect(a.street, 'Jalan Diponegoro 45');
      expect(a.city, 'Surabaya');
    });

    test('alamat di ruko tanpa kata "Jalan"', () {
      const String raw = 'KOPI KENANGAN\n'
          'Ruko Galaxy Blok A2\n'
          'Bekasi Selatan, Kota Bekasi\n'
          '05/10/2026\n'
          'Kopi Susu 18.000';

      final StoreAddress a = extractor.extract(raw, merchantName: 'Kopi Kenangan');

      expect(a.street, 'Ruko Galaxy Blok A2');
      expect(a.city, 'Kota Bekasi');
    });

    test('struk tanpa alamat menghasilkan alamat kosong', () {
      const String raw = 'KEDAI KOPI\n01/10/2026\nKopi Susu 18.000\nTotal 18.000';

      expect(extractor.extract(raw).isEmpty, isTrue);
    });

    test('kueri geocoding bertingkat dari rinci ke kasar', () {
      const String raw = 'INDOMARET\n'
          'UREK UREK\n'
          'JL. RAYA UREK UREK\n'
          'KEC GONDANGLEGI, KAB MALANG, 65174\n'
          '13/11/2026';

      final StoreAddress a = extractor.extract(raw, merchantName: 'Indomaret');
      final List<AddressQuery> q = a.geocodeQueries('Indomaret');

      expect(q.first.precision, LocationPrecision.store);
      expect(q.first.text, 'Indomaret Urek Urek, Kabupaten Malang');
      // Tanpa awalan "Kecamatan" (Nominatim tidak menemukan hasil bila ada).
      expect(q.any((AddressQuery e) => e.text.contains('Kecamatan')), isFalse);
      expect(q.map((AddressQuery e) => e.text), contains('Gondanglegi, Kabupaten Malang'));
      expect(q.map((AddressQuery e) => e.text),
          contains('Jalan Urek Urek, Kabupaten Malang'),
          reason: 'varian tanpa "Raya"');
      expect(q.map((AddressQuery e) => e.precision),
          containsAllInOrder(<LocationPrecision>[
            LocationPrecision.store,
            LocationPrecision.street,
            LocationPrecision.district,
            LocationPrecision.postalCode,
            LocationPrecision.city,
          ]));
    });

    test('ParsingService ikut mengisi alamat toko', () {
      const String raw = 'INDOMARET\n'
          'Jl. Raya Malang\n'
          '01/10/2026\n'
          'Roti 12.000\n'
          'TOTAL 12.000';

      final ParsedReceiptData result = const ParsingService().parse(raw);

      expect(result.merchantName, 'Indomaret');
      expect(result.address.street, 'Jalan Raya Malang');
    });
  });
}
