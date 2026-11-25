import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smart_receipt/core/utils/formatters.dart';
import 'package:smart_receipt/services/ocr_text_corrector.dart';
import 'package:smart_receipt/services/parsing_service.dart';
import 'package:smart_receipt/services/receipt_selector.dart';

/// Hasil OCR struk Wizzmie persis seperti yang dibaca aplikasi: logo rusak,
/// "M" pada Muharto dan Malang hilang, "Table" jadi "Taple", "Rounding" jadi
/// "Rcunding", angka qty di depan "Ice Tea" hilang, dan Grand Total "41.000"
/// terbaca "4.00".
const String wizzmieOcr = 'W/ZZmne\n'
    'Wizzmie uharto Nalang\n'
    'No :WAM202611230(91\n'
    'Date :23-11-2026 16:58\n'
    'Info :Satryaaa\n'
    'Taple :16\n'
    'Purpose : DINE IN\n'
    'Pax :2\n'
    'Cashier\n'
    'ÍCe Tea 13.636\n'
    '2 Mie Disko Ly 1 23.726\n'
    '4 items\n'
    'Subtotal: 37.362\n'
    'PB1 : 3.736\n'
    'Total : 41.098\n'
    'Rcunding: -98\n'
    'Grand Total : 4.00\n'
    'CASH : 51.000\n'
    'Change: 10.000';

Map<String, double> totals(ParsedReceiptData r) => <String, double>{
      for (final ParsedItem i in r.items) i.name: i.totalPrice,
    };

void main() {
  const ParsingService parser = ParsingService();

  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  group('Struk Wizzmie (hasil OCR yang rusak)', () {
    late ParsedReceiptData r;
    setUp(() => r = parser.parse(wizzmieOcr));

    test('nama toko: logo rusak diganti baris lengkap, tanpa cabang dan kota',
        () {
      expect(r.merchantName, 'Wizzmie');
    });

    test('tanggal terbaca dari "23-11-2026 16:58"', () {
      expect(r.transactionDate, DateTime(2026, 11, 23));
    });

    test('barang dengan jumlahnya, termasuk "Lv 1" dan qty yang hilang', () {
      expect(totals(r), <String, double>{
        'Ice Tea': 13636,
        'Mie Disko Lv 1': 23726,
      });
      final ParsedItem tea = r.items.firstWhere((i) => i.name == 'Ice Tea');
      final ParsedItem mie =
          r.items.firstWhere((i) => i.name == 'Mie Disko Lv 1');
      expect(mie.quantity, 2, reason: 'angka di depan nama');
      expect(tea.quantity, 2,
          reason: '"4 items" dikurangi 2 mie = 2 teh (angkanya terpotong OCR)');
      expect(tea.unitPrice, closeTo(6818, 1));
      expect(r.itemsCount, 4);
    });

    test('baris kunci-nilai (Info, Table, Pax, Cashier) bukan barang', () {
      final Iterable<String> names =
          r.items.map((ParsedItem i) => i.name.toLowerCase());
      for (final String junk in <String>[
        'info',
        'table',
        'pax',
        'cashier',
        'purpose'
      ]) {
        expect(names.any((String n) => n.contains(junk)), isFalse,
            reason: junk);
      }
    });

    test(
        'ringkasan: subtotal, PB1, pembulatan, dan grand total yang dipulihkan',
        () {
      expect(r.subtotal, 37362);
      expect(r.taxAmount, 3736);
      expect(r.taxLabel, 'PB1');
      expect(r.roundingAmount, -98);
      expect(r.totalAmount, 41000,
          reason: 'Grand Total terbaca "4.00"; dipulihkan dari 41.098 − 98');
      expect(r.totalFromKeyword, isTrue);
      expect(r.itemsTarget, 37362);
      expect(r.itemsTotal, 37362);
    });

    test('rincian menjelaskan selisih subtotal dan total', () {
      expect(
        r.breakdownText(AppFormatters.rupiah),
        'Subtotal ${AppFormatters.rupiah(37362)} + PB1 ${AppFormatters.rupiah(3736)} '
        '− Pembulatan ${AppFormatters.rupiah(98)} = ${AppFormatters.rupiah(41000)}',
      );
    });

    test('alamat dari judul toko: cabang Muharto, Jalan Muharto, Malang', () {
      expect(r.address.branchName, 'Muharto');
      expect(r.address.street, 'Jalan Muharto');
      expect(r.address.city, 'Malang');
      expect(r.address.fullAddress, 'Jalan Muharto, Malang');
      expect(r.address.geocodeQueries(r.merchantName).first.text,
          'Wizzmie Muharto, Malang');
    });

    test('huruf yang hilang atau tertukar dikoreksi dan dilaporkan', () {
      final List<String> shown =
          r.corrections.map((TextCorrection c) => c.toString()).toList();
      expect(
          shown,
          containsAll(<String>[
            'uharto → Muharto',
            'Nalang → Malang',
            'Rcunding → Rounding',
            'Taple → Table',
          ]));
      expect(shown.any((String c) => c.contains('Disko')), isFalse,
          reason: 'nama menu tidak boleh diubah jadi "Diskon"');
    });

    test('struk dianggap lengkap dan konsisten (tidak perlu foto diperjelas)',
        () {
      const ReceiptSelector selector = ReceiptSelector();
      expect(selector.isConsistent(r), isTrue);
      expect(selector.isComplete(r), isTrue);
    });
  });

  group('Pengoreksi kata OCR', () {
    const OcrTextCorrector c = OcrTextCorrector();

    test('kata kunci struk yang huruf miripnya tertukar', () {
      expect(c.correctLine('Rcunding: -98'), 'Rounding: -98');
      expect(c.correctLine('Taple :16'), 'Table :16');
      expect(c.correctLine('Grand Totai : 41.000'), 'Grand Total : 41.000');
      expect(c.correctLine('Tota1 41.098'), 'Total 41.098',
          reason: 'angka 1 = huruf l');
      expect(c.correctLine('Cashier : CSO'), 'Cashier : CSO',
          reason: 'sudah benar');
    });

    test('satu huruf hilang diperbaiki pada baris judul', () {
      expect(c.correctLine('Wizzmie uharto Nalang'), 'Wizzmie Muharto Malang');
      expect(c.correctLine('Toko Maju Malng'), 'Toko Maju Malang');
    });

    test('pada baris berharga, huruf hilang TIDAK diperbaiki (nama menu)', () {
      expect(c.correctLine('Mie Disko 23.726', lenient: false),
          'Mie Disko 23.726');
      expect(
          c.correctLine('Disko Tea 5.000', lenient: false), 'Disko Tea 5.000');
    });

    test('kata benar dan merek tak dikenal tidak diubah', () {
      expect(c.correctLine('Bandeng Presto Malang'), 'Bandeng Presto Malang',
          reason: 'bandeng bukan salah baca Bandung');
      expect(c.correctLine('Wizzmie'), 'Wizzmie');
      expect(c.correctLine('Satryaaa'), 'Satryaaa');
    });

    test('aksen dihilangkan dan huruf besar yang menyelip dirapikan', () {
      expect(OcrTextCorrector.foldAccents('ÍCe Tea'), 'ICe Tea');
      expect(OcrTextCorrector.normalizeCase('ICe'), 'Ice');
      expect(OcrTextCorrector.normalizeCase('iPhone'), 'iPhone');
      expect(OcrTextCorrector.normalizeCase('USB'), 'USB');
    });

    test('jarak sunting: huruf mirip lebih murah daripada huruf acak', () {
      expect(OcrTextCorrector.distance('nalang', 'malang'), 0.5);
      expect(OcrTextCorrector.distance('kalang', 'malang'), 1.0);
      expect(OcrTextCorrector.distance('malng', 'malang'), 1.0);
    });
  });

  group('Format struk lain', () {
    test('restoran: service + PB1, jumlah x harga satuan', () {
      final ParsedReceiptData r = parser.parse(
        'RM PADANG SALERO\n'
        'Jl. Veteran No 12, Malang\n'
        '12/11/2026 12:30\n'
        'Nasi Rendang 2 x 25.000 50.000\n'
        'Es Teh Manis 2 x 5.000 10.000\n'
        'Subtotal 60.000\n'
        'Service 5% 3.000\n'
        'PB1 10% 6.300\n'
        'Total 69.300\n'
        'Tunai 70.000\n'
        'Kembali 700',
      );

      expect(r.merchantName, 'Rm Padang Salero');
      expect(totals(r),
          <String, double>{'Nasi Rendang': 50000, 'Es Teh Manis': 10000});
      expect(r.subtotal, 60000);
      expect(r.serviceAmount, 3000);
      expect(r.taxAmount, 6300);
      expect(r.totalAmount, 69300);
      expect(r.address.street, 'Jalan Veteran');
      expect(r.address.houseNumber, '12');
    });

    test('kafe: harga berkoma, qty di depan, pajak, Grand Total', () {
      final ParsedReceiptData r = parser.parse(
        'STARBUCKS COFFEE\n'
        'Mall Ciputra World Surabaya\n'
        '23/11/2026\n'
        '1 Caffe Latte Grande 55,000\n'
        '1 Choco Muffin 32,000\n'
        'Subtotal 87,000\n'
        'Tax 10% 8,700\n'
        'Grand Total 95,700',
      );

      expect(totals(r), <String, double>{
        'Caffe Latte Grande': 55000,
        'Choco Muffin': 32000,
      });
      expect(r.totalAmount, 95700);
      expect(r.subtotal, 87000);
      expect(r.taxAmount, 8700);
      expect(r.itemsTarget, 87000);
    });

    test('apotek: harga berawalan Rp dan total Rp', () {
      final ParsedReceiptData r = parser.parse(
        'APOTEK K24\n'
        'Jl. Soekarno Hatta 100 Malang\n'
        '05/11/2026\n'
        'Paracetamol 500mg 2 x 4.500 9.000\n'
        'Vitamin C 1000mg 1 x 35.000 35.000\n'
        'Total Rp 44.000\n'
        'Bayar Rp 50.000',
      );

      expect(r.merchantName, 'Apotek K24');
      expect(totals(r), <String, double>{
        'Paracetamol 500mg': 9000,
        'Vitamin C 1000mg': 35000,
      });
      expect(r.totalAmount, 44000);
    });

    test('parkir: satu baris layanan dan total', () {
      final ParsedReceiptData r = parser.parse(
        'PARKIR MALL OLYMPIC GARDEN\n'
        'Tgl 10/11/2026 14:00\n'
        'Motor 1 Jam 2.000\n'
        'Total 2.000',
      );

      expect(r.totalAmount, 2000);
      expect(r.transactionDate, DateTime(2026, 11, 10));
      expect(r.items, isNotEmpty);
      expect(r.itemsTotal, 2000);
    });

    test('minimarket: diskon member pada barang dan potongan di ringkasan', () {
      final ParsedReceiptData r = parser.parse(
        'ALFAMART\n'
        'JL. SIMPANG BALAPAN 5 MALANG\n'
        '13/11/26 20:51\n'
        'TEH BOTOL SOSRO 450ML 2 5.500 11.000\n'
        'INDOMIE GORENG 3 3.200 9.600\n'
        'DISC MEMBER -1.000\n'
        'SUBTOTAL 20.600\n'
        'POTONGAN 1.000\n'
        'TOTAL 19.600\n'
        'TUNAI 20.000\n'
        'KEMBALI 400',
      );

      expect(r.merchantName, 'Alfamart');
      expect(r.totalAmount, 19600);
      expect(r.subtotal, 20600);
      expect(r.items.map((ParsedItem i) => i.name),
          <String>['TEH BOTOL SOSRO 450ML', 'INDOMIE GORENG']);
      expect(r.itemsTotal, 19600, reason: 'diskon sudah memotong barangnya');
      expect(const ReceiptSelector().isConsistent(r), isTrue,
          reason: 'barang cocok dengan subtotal setelah diskon');
    });

    test('laundry: berat kg dan satuan pcs', () {
      final ParsedReceiptData r = parser.parse(
        'LAUNDRY BERSIH KILAT\n'
        'Tgl 01/11/2026\n'
        'Cuci Setrika 5 kg 7.000 35.000\n'
        'Bed Cover 1 pcs 25.000\n'
        'Total 60.000',
      );

      expect(totals(r),
          <String, double>{'Cuci Setrika': 35000, 'Bed Cover': 25000});
      expect(r.totalAmount, 60000);
    });

    test('token listrik: nominal dan biaya admin', () {
      final ParsedReceiptData r = parser.parse(
        'PLN PREPAID\n'
        'Tgl 02/11/2026\n'
        'Token Listrik 100.000\n'
        'Admin Bank 2.500\n'
        'Total Bayar 102.500',
      );

      expect(totals(r),
          <String, double>{'Token Listrik': 100000, 'Admin Bank': 2500});
      expect(r.totalAmount, 102500);
    });

    test('transportasi online: biaya layanan sebelum total adalah barang', () {
      final ParsedReceiptData r = parser.parse(
        'GOJEK\n'
        'Tgl 03/11/2026\n'
        'Biaya Perjalanan 18.000\n'
        'Biaya Layanan 2.000\n'
        'Total 20.000',
      );

      expect(r.totalAmount, 20000);
      expect(r.itemsTotal, 20000);
      expect(r.serviceAmount, isNull,
          reason: 'bukan tambahan setelah subtotal');
    });

    test('supermarket: "Total Item 3" bukan total, PPN 11%', () {
      final ParsedReceiptData r = parser.parse(
        'HYPERMART\n'
        'Jl. Raya Bogor 5 Depok\n'
        '20/11/2026 18:00\n'
        'BERAS RAJALELE 5KG 1 65.000 65.000\n'
        'MINYAK GORENG 2L 2 32.000 64.000\n'
        'Total Item 3\n'
        'Subtotal 129.000\n'
        'PPN 11% 14.190\n'
        'Total 143.190',
      );

      expect(totals(r), <String, double>{
        'BERAS RAJALELE 5KG': 65000,
        'MINYAK GORENG 2L': 64000,
      });
      expect(r.totalAmount, 143190);
      expect(r.subtotal, 129000);
      expect(r.taxAmount, 14190);
      expect(r.taxLabel, 'PPN');
    });

    test('total struk yang tertulis kurang digit dipulihkan dari rincian', () {
      final ParsedReceiptData r = parser.parse(
        'KEDAI MIE\n'
        '01/11/2026\n'
        'Mie Pedas 2 x 15.000 30.000\n'
        'Subtotal 30.000\n'
        'PB1 3.000\n'
        'Grand Total : 3.00',
      );

      expect(r.totalAmount, 33000);
    });

    test('kata kunci yang rusak tetap terbaca (Subtotl, Grand Totai, Kernbali)',
        () {
      final ParsedReceiptData r = parser.parse(
        'TOKO MURAH\n'
        '01/11/2026\n'
        'Gula Pasir 1kg 15.000\n'
        'Subtotl 15.000\n'
        'Grand Totai 15.000\n'
        'Tunai 20.000\n'
        'Kernbali 5.000',
      );

      expect(r.totalAmount, 15000);
      expect(totals(r), <String, double>{'Gula Pasir 1kg': 15000});
    });
  });
}
