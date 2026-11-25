import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/services/parsing_service.dart';
import 'package:smart_receipt/services/receipt_selector.dart';
import 'package:smart_receipt/services/store_address_extractor.dart';

/// Format letak alamat yang berbeda-beda pada struk nyata.
void main() {
  const StoreAddressExtractor extractor = StoreAddressExtractor();

  group('Letak dan bentuk alamat', () {
    test('tanggal ditulis SEBELUM alamat', () {
      const String raw = 'ALFAMART\n'
          '12/10/2026 10:21\n'
          'JL. MERDEKA NO 5\n'
          'KEL. SUKAJADI KEC. SUKASARI\n'
          'KOTA BANDUNG 40162\n'
          'ROTI 12.000\n'
          'TOTAL 12.000';

      final StoreAddress a = extractor.extract(raw, merchantName: 'Alfamart');

      expect(a.street, 'Jalan Merdeka');
      expect(a.houseNumber, '5');
      expect(a.village, 'Sukajadi');
      expect(a.district, 'Sukasari');
      expect(a.city, 'Kota Bandung');
      expect(a.postalCode, '40162');
    });

    test('alamat di KAKI struk, bukan kepala', () {
      const String raw = 'TOKO MAKMUR\n'
          '01/10/2026\n'
          'Gula 14.500\n'
          'Minyak 32.000\n'
          'TOTAL 46.500\n'
          'TUNAI 50.000\n'
          'Terima kasih\n'
          'Jl. Gatot Subroto No. 10, Medan';

      final StoreAddress a =
          extractor.extract(raw, merchantName: 'Toko Makmur');

      expect(a.street, 'Jalan Gatot Subroto');
      expect(a.houseNumber, '10');
      expect(a.city, 'Medan');
    });

    test('alamat berlabel "Alamat:" dan memakai gang (Gg.)', () {
      const String raw = 'TOKO ABC\n'
          'Alamat: Gg. Mawar No 3, Kel. Pasirkaliki\n'
          'Kota Bandung 40171\n'
          '01/10/2026\n'
          'Sabun 5.000\n'
          'TOTAL 5.000';

      final StoreAddress a = extractor.extract(raw, merchantName: 'Toko Abc');

      expect(a.street, 'Gang Mawar');
      expect(a.houseNumber, '3');
      expect(a.village, 'Pasirkaliki');
      expect(a.city, 'Kota Bandung');
    });

    test('komponen tak dikenali: alamat tetap terisi sebagai teks bebas', () {
      const String raw = 'WARUNG SEDERHANA\n'
          'Alamat: Griya Asri Kav 12\n'
          '01/10/2026\n'
          'Nasi 15.000\n'
          'TOTAL 15.000';

      final StoreAddress a =
          extractor.extract(raw, merchantName: 'Warung Sederhana');

      expect(a.isEmpty, isFalse);
      expect(a.hasComponents, isFalse);
      expect(a.fullAddress, 'Griya Asri Kav 12');
      expect(
          a.geocodeQueries('Warung Sederhana').first.text, 'Griya Asri Kav 12');
    });

    test('baris telepon tidak memutus pembacaan alamat', () {
      const String raw = 'SURYA ELEKTRONIK\n'
          'Telp. 0411 3628529\n'
          'Jl. Veteran Utara No.248B\n'
          'Makassar\n'
          '16/11/2019\n'
          'PPG 500.000';

      final StoreAddress a = extractor.extract(raw);

      expect(a.street, 'Jalan Veteran Utara');
      expect(a.city, 'Makassar');
    });

    test('struk tanpa alamat tidak mengarang alamat dari nama barang', () {
      const String raw = 'KEDAI KOPI\n'
          '01/10/2026\n'
          'Kopi Susu 18.000\n'
          'Roti Bakar 15.000\n'
          'Total 33.000\n'
          'Terima kasih';

      expect(extractor.extract(raw).isEmpty, isTrue);
    });
  });

  group('Alamat tidak hilang saat foto diperjelas', () {
    test('ReceiptSelector.choose membawa alamat dari bacaan lain', () {
      const ParsingService parser = ParsingService();
      const ReceiptSelector selector = ReceiptSelector();

      // Foto asli: alamat terbaca tetapi barang tidak lengkap.
      final ReceiptReading original = ReceiptReading(
        rawText: 'INDOMARET\nJl. Raya Malang\n01/10/2026\nRoti 12.000',
        parsed:
            parser.parse('INDOMARET\nJl. Raya Malang\n01/10/2026\nRoti 12.000'),
      );
      // Foto diperjelas: barang lengkap dan cocok dengan total, alamat hilang.
      const String enhancedText = 'INDOMARET\n'
          '01/10/2026\n'
          'Roti 12.000\n'
          'Air Mineral 5.000\n'
          'TOTAL 17.000';
      final ReceiptReading enhanced = ReceiptReading(
        rawText: enhancedText,
        parsed: parser.parse(enhancedText),
        fromEnhancedImage: true,
      );

      final ReceiptReading chosen = selector.choose(original, enhanced);

      expect(chosen.fromEnhancedImage, isTrue,
          reason: 'bacaan kedua lebih lengkap sehingga dipilih');
      expect(chosen.parsed.items, hasLength(2));
      expect(chosen.parsed.address.street, 'Jalan Raya Malang',
          reason: 'alamat dari bacaan pertama tidak boleh hilang');
    });
  });
}
