import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/services/mcc_categories.dart';
import 'package:smart_receipt/services/qris_parser.dart';

/// Template bersarang (mis. isi tag 51) dalam format TLV.
String nested(Map<String, String> fields) => fields.entries
    .map((MapEntry<String, String> e) =>
        '${e.key}${e.value.length.toString().padLeft(2, '0')}${e.value}')
    .join();

/// QRIS statis seperti yang ditempel di meja warung.
String staticQris({
  String name = 'WARUNG BU SITI',
  String city = 'MALANG',
  String mcc = '5812',
  String nmid = 'ID1020012345678',
  String? storeLabel,
}) =>
    QrisParser.build(<String, String>{
      '00': '01',
      '01': '11',
      '51': nested(<String, String>{
        '00': 'ID.CO.QRIS.WWW',
        '02': nmid,
        '03': 'UMI',
      }),
      '52': mcc,
      '53': '360',
      '58': 'ID',
      '59': name,
      '60': city,
      '61': '65145',
      if (storeLabel != null) '62': nested(<String, String>{'03': storeLabel}),
    });

/// QRIS dinamis: kasir sudah memasukkan nominal.
String dynamicQris({
  String amount = '41000.00',
  Map<String, String> extra = const <String, String>{},
}) =>
    QrisParser.build(<String, String>{
      '00': '01',
      '01': '12',
      '51': nested(<String, String>{
        '00': 'ID.CO.QRIS.WWW',
        '02': 'ID1020099887766',
        '03': 'UKE',
      }),
      '52': '5812',
      '53': '360',
      '54': amount,
      ...extra,
      '58': 'ID',
      '59': 'WIZZMIE MUHARTO',
      '60': 'MALANG',
      '61': '65125',
    });

void main() {
  const QrisParser parser = QrisParser();

  group('CRC-16', () {
    test('cocok dengan vektor uji baku CRC-16/CCITT-FALSE', () {
      expect(QrisParser.crcHex('123456789'), '29B1');
      expect(QrisParser.crcHex(''), 'FFFF');
    });
  });

  group('QRIS statis', () {
    test('membaca nama, kota, MCC, NMID, dan jenis usaha', () {
      final QrisData q = parser.parse(staticQris());

      expect(q.isDynamic, isFalse);
      expect(q.merchantName, 'Warung Bu Siti');
      expect(q.city, 'Malang');
      expect(q.postalCode, '65145');
      expect(q.mcc, '5812');
      expect(q.merchantId, 'ID1020012345678');
      expect(q.criteria, 'UMI');
      expect(q.categoryName, 'Konsumsi');
      expect(q.businessLabel, 'Restoran');
    });

    test('tanpa nominal: pengguna harus mengetik sendiri', () {
      final QrisData q = parser.parse(staticQris());

      expect(q.amount, isNull);
      expect(q.hasAmount, isFalse);
      expect(q.totalAmount, isNull);
    });

    test('label toko (tag 62) terbaca sebagai cabang', () {
      final QrisData q = parser.parse(staticQris(storeLabel: 'CABANG DINOYO'));
      expect(q.storeLabel, 'Cabang Dinoyo');
    });

    test('nama yang sudah bercampur huruf besar kecil dibiarkan', () {
      final QrisData q = parser.parse(staticQris(name: 'Kopi Tuku 24'));
      expect(q.merchantName, 'Kopi Tuku 24');
    });

    test('huruf kecil pada CRC tetap diterima', () {
      final String payload = staticQris();
      final String lower = payload.substring(0, payload.length - 4) +
          payload.substring(payload.length - 4).toLowerCase();
      expect(parser.parse(lower).merchantName, 'Warung Bu Siti');
    });

    test('NMID dicari pada template penyelenggara bila tag 51 tidak ada', () {
      final String payload = QrisParser.build(<String, String>{
        '00': '01',
        '01': '11',
        '26': nested(<String, String>{
          '00': 'ID.CO.EXAMPLE.WWW',
          '01': '9360001234567890',
        }),
        '52': '5411',
        '53': '360',
        '58': 'ID',
        '59': 'TOKO MAKMUR',
        '60': 'SURABAYA',
      });

      final QrisData q = parser.parse(payload);
      expect(q.merchantId, '9360001234567890');
      expect(q.categoryName, 'Bahan Makanan');
    });
  });

  group('QRIS dinamis', () {
    test('memuat nominal', () {
      final QrisData q = parser.parse(dynamicQris());

      expect(q.isDynamic, isTrue);
      expect(q.amount, 41000);
      expect(q.hasAmount, isTrue);
      expect(q.totalAmount, 41000);
      expect(q.merchantName, 'Wizzmie Muharto');
      expect(q.criteria, 'UKE');
    });

    test('nominal berkoma desimal dan tanpa desimal', () {
      expect(parser.parse(dynamicQris(amount: '15000')).amount, 15000);
      expect(parser.parse(dynamicQris(amount: '15000,50')).amount, 15000.5);
    });

    test('biaya layanan tetap (tag 55=02, 56) ditambahkan ke total', () {
      final QrisData q = parser.parse(dynamicQris(
        extra: <String, String>{'55': '02', '56': '2500'},
      ));

      expect(q.amount, 41000);
      expect(q.fixedFee, 2500);
      expect(q.totalAmount, 43500);
    });

    test('biaya persentase (tag 55=03, 57) ditambahkan ke total', () {
      final QrisData q = parser.parse(dynamicQris(
        amount: '100000',
        extra: <String, String>{'55': '03', '57': '0.7'},
      ));

      expect(q.percentFee, 0.7);
      expect(q.totalAmount, closeTo(100700, 0.001));
    });

    test('permintaan tip (tag 55=01) dikenali', () {
      final QrisData q =
          parser.parse(dynamicQris(extra: <String, String>{'55': '01'}));
      expect(q.tipPrompt, isTrue);
      expect(q.totalAmount, 41000);
    });

    test('nominal nol atau negatif dianggap tidak ada', () {
      expect(parser.parse(dynamicQris(amount: '0')).hasAmount, isFalse);
    });
  });

  group('QR yang tidak valid', () {
    QrisError errorOf(String payload) {
      try {
        parser.parse(payload);
      } on QrisParseException catch (e) {
        return e.error;
      }
      fail('seharusnya gagal dibaca');
    }

    test('QR biasa (situs web, teks) bukan QRIS', () {
      expect(errorOf('https://example.com/toko'), QrisError.notQris);
      expect(errorOf('Halo dunia'), QrisError.notQris);
      expect(errorOf(''), QrisError.notQris);
      expect(parser.looksLikeQris('https://example.com'), isFalse);
      expect(parser.looksLikeQris(staticQris()), isTrue);
    });

    test('satu karakter berubah: CRC tidak cocok', () {
      final String good = staticQris();
      final String tampered = good.replaceFirst('BU SITI', 'BU SITA');
      expect(errorOf(tampered), QrisError.badChecksum);
    });

    test('nominal diubah setelah dibuat: terdeteksi', () {
      final String good = dynamicQris(amount: '41000.00');
      expect(errorOf(good.replaceFirst('41000.00', '10000.00')),
          QrisError.badChecksum);
    });

    test('data terpotong atau panjang tidak cocok', () {
      expect(errorOf('00020101021159'), QrisError.malformed);
      expect(errorOf('0002010102115912ABC'), QrisError.malformed);
    });

    test('tanpa kode CRC di akhir', () {
      expect(errorOf('00020101021152045812'), QrisError.badChecksum);
    });

    test('tanpa nama merchant', () {
      final String payload = QrisParser.build(<String, String>{
        '00': '01',
        '01': '11',
        '52': '5812',
        '53': '360',
        '58': 'ID',
        '60': 'MALANG',
      });
      expect(errorOf(payload), QrisError.missingMerchant);
    });

    test('pesan galat berbahasa Indonesia dan jelas', () {
      expect(const QrisParseException(QrisError.notQris).message,
          contains('bukan kode QRIS'));
      expect(const QrisParseException(QrisError.badChecksum).message,
          contains('tidak valid'));
    });
  });

  group('MCC ke kategori', () {
    test('kode umum', () {
      expect(MccCategories.of('5812'), 'Konsumsi');
      expect(MccCategories.of('5814'), 'Konsumsi');
      expect(MccCategories.of('5411'), 'Bahan Makanan');
      expect(MccCategories.of('5541'), 'Transportasi');
      expect(MccCategories.of('7523'), 'Transportasi');
      expect(MccCategories.of('5912'), 'Kesehatan');
      expect(MccCategories.of('5732'), 'Elektronik');
      expect(MccCategories.of('7210'), 'Jasa & Layanan');
      expect(MccCategories.of('4900'), 'Tagihan & Utilitas');
      expect(MccCategories.of('8398'), 'Donasi & Sosial');
      expect(MccCategories.of('7832'), 'Hiburan');
      expect(MccCategories.of('5942'), 'Pendidikan');
      expect(MccCategories.of('5311'), 'Belanja');
    });

    test('rentang kode', () {
      expect(MccCategories.of('8011'), 'Kesehatan');
      expect(MccCategories.of('8031'), 'Kesehatan');
      expect(MccCategories.of('8299'), 'Pendidikan');
      expect(MccCategories.of('5655'), 'Pakaian & Aksesori');
    });

    test('tidak dikenal atau tidak valid menjadi Lainnya', () {
      expect(MccCategories.of('9999'), 'Lainnya');
      expect(MccCategories.of('abcd'), 'Lainnya');
      expect(MccCategories.of(''), 'Lainnya');
      expect(MccCategories.of(null), 'Lainnya');
    });

    test('semua nama kategori hasil pemetaan ada pada kategori bawaan', () {
      const Set<String> valid = <String>{
        'Konsumsi',
        'Transportasi',
        'Kesehatan',
        'Belanja',
        'Lainnya',
        'Elektronik',
        'Bahan Makanan',
        'Perawatan Diri',
        'Rumah Tangga',
        'Pakaian & Aksesori',
        'Pendidikan',
        'Hiburan',
        'Tagihan & Utilitas',
        'Jasa & Layanan',
        'Donasi & Sosial',
      };
      for (int code = 0; code <= 9999; code++) {
        expect(
            valid, contains(MccCategories.of(code.toString().padLeft(4, '0'))),
            reason: 'MCC $code');
      }
    });
  });
}
