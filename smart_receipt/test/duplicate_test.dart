import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/data/models/transaction_item_model.dart';
import 'package:smart_receipt/data/models/transaction_model.dart';
import 'package:smart_receipt/data/repositories/transaction_repository.dart';
import 'package:smart_receipt/services/duplicate_detector.dart';
import 'package:smart_receipt/viewmodels/scan_viewmodel.dart';

import 'viewmodels_test.dart'
    show FakeTransactionRepository, readyScan, sampleReceipt;

/// Repository tiruan dengan satu transaksi lama beserta barangnya.
class _OneTransactionRepository extends Fake implements TransactionRepository {
  _OneTransactionRepository(this.transaction, this.itemNames);

  final TransactionModel transaction;
  final List<String> itemNames;

  @override
  Future<List<TransactionModel>> findSameDayAmount(
    int userId,
    DateTime date,
    double total, {
    double tolerance = 1,
  }) async {
    final DateTime d = transaction.transactionDate;
    final bool same = transaction.userId == userId &&
        d.year == date.year &&
        d.month == date.month &&
        d.day == date.day &&
        (transaction.totalAmount - total).abs() <= tolerance;
    return same ? <TransactionModel>[transaction] : <TransactionModel>[];
  }

  @override
  Future<List<TransactionItemModel>> getItems(int transactionId) async {
    final DateTime now = DateTime(2026, 10, 1);
    return <TransactionItemModel>[
      for (final String name in itemNames)
        TransactionItemModel(
          transactionId: transactionId,
          name: name,
          quantity: 1,
          unitPrice: 1000,
          totalPrice: 1000,
          categoryId: 1,
          createdAt: now,
        ),
    ];
  }
}

TransactionModel stored({
  String merchant = 'Indomaret',
  DateTime? date,
  double total = 17000,
}) {
  final DateTime now = DateTime(2026, 10, 2);
  return TransactionModel(
    id: 7,
    userId: 1,
    merchantName: merchant,
    transactionDate: date ?? DateTime(2026, 10, 1),
    totalAmount: total,
    categoryId: 1,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> settle() async {
  for (int i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('Kemiripan toko dan barang', () {
    test('nama toko yang sama walau beda huruf besar atau tambahan cabang', () {
      expect(
          DuplicateDetector.merchantsSimilar('Indomaret', 'INDOMARET'), isTrue);
      expect(
          DuplicateDetector.merchantsSimilar(
              'Indomaret', 'Indomaret Urek Urek'),
          isTrue);
      expect(
          DuplicateDetector.merchantsSimilar(
              'Surya Elektronik', 'Surya Elektronk'),
          isTrue,
          reason: 'salah baca OCR satu huruf');
    });

    test('toko berbeda tidak dianggap mirip', () {
      expect(
          DuplicateDetector.merchantsSimilar('Alfamart', 'Indomaret'), isFalse);
      expect(DuplicateDetector.merchantsSimilar('', 'Indomaret'), isFalse);
    });

    test('kesamaan barang diukur dari daftar nama', () {
      expect(
        DuplicateDetector.itemOverlap(
          <String>['Roti', 'Air Mineral'],
          <String>['ROTI', 'air mineral 600ml'],
        ),
        1.0,
      );
      expect(
        DuplicateDetector.itemOverlap(
          <String>['Roti', 'Susu'],
          <String>['Sabun', 'Sampo'],
        ),
        0.0,
      );
    });
  });

  group('DuplicateDetector', () {
    test('struk yang sama dipindai dua kali: hampir pasti ganda', () async {
      final DuplicateDetector detector = DuplicateDetector(
        _OneTransactionRepository(stored(), <String>['Roti', 'Air Mineral']),
      );

      final List<DuplicateMatch> found = await detector.find(
        userId: 1,
        date: DateTime(2026, 10, 1),
        total: 17000,
        merchantName: 'Indomaret',
        itemNames: <String>['Roti', 'Air Mineral'],
      );

      expect(found, hasLength(1));
      expect(found.first.isLikely, isTrue);
      expect(found.first.reasons,
          containsAll(<String>['Toko sama', 'Tanggal sama', 'Total sama']));
      expect(found.first.reasons, contains('100% barang sama'));
    });

    test('nama toko salah baca tetapi barangnya sama: tetap ditandai',
        () async {
      final DuplicateDetector detector = DuplicateDetector(
        _OneTransactionRepository(
            stored(merchant: 'Indomaret'), <String>['Roti', 'Air Mineral']),
      );

      final List<DuplicateMatch> found = await detector.find(
        userId: 1,
        date: DateTime(2026, 10, 1),
        total: 17000,
        merchantName: 'Lndomrt',
        itemNames: <String>['Roti', 'Air Mineral'],
      );

      expect(found, hasLength(1));
      expect(found.first.reasons, isNot(contains('Toko sama')));
    });

    test('tanggal dan total kebetulan sama pada toko berbeda: tidak ditandai',
        () async {
      final DuplicateDetector detector = DuplicateDetector(
        _OneTransactionRepository(
            stored(merchant: 'Apotek Sehat'), <String>['Paracetamol']),
      );

      final List<DuplicateMatch> found = await detector.find(
        userId: 1,
        date: DateTime(2026, 10, 1),
        total: 17000,
        merchantName: 'Indomaret',
        itemNames: <String>['Roti', 'Air Mineral'],
      );

      expect(found, isEmpty);
    });

    test('total atau tanggal berbeda: bukan ganda', () async {
      final DuplicateDetector detector = DuplicateDetector(
        _OneTransactionRepository(stored(), <String>['Roti']),
      );

      expect(
        await detector.find(
          userId: 1,
          date: DateTime(2026, 10, 1),
          total: 17500,
          merchantName: 'Indomaret',
          itemNames: <String>['Roti'],
        ),
        isEmpty,
      );
      expect(
        await detector.find(
          userId: 1,
          date: DateTime(2026, 10, 2),
          total: 17000,
          merchantName: 'Indomaret',
          itemNames: <String>['Roti'],
        ),
        isEmpty,
      );
    });
  });

  group('ScanViewModel - struk ganda', () {
    test('struk yang sama dipindai ulang memunculkan peringatan', () async {
      final FakeTransactionRepository repo = FakeTransactionRepository();

      final ScanViewModel first = await readyScan(sampleReceipt, repo);
      await settle();
      expect(first.duplicates, isEmpty, reason: 'struk pertama belum ganda');
      expect(await first.saveTransaction(), isTrue);

      final ScanViewModel second = await readyScan(sampleReceipt, repo);
      await settle();

      expect(second.duplicates, hasLength(1));
      expect(second.duplicates.first.isLikely, isTrue);
      expect(second.duplicates.first.transaction.merchantName, 'Indomaret');
    });

    test('mengubah tanggal menghapus peringatan', () async {
      final FakeTransactionRepository repo = FakeTransactionRepository();
      final ScanViewModel first = await readyScan(sampleReceipt, repo);
      await first.saveTransaction();

      final ScanViewModel second = await readyScan(sampleReceipt, repo);
      await settle();
      expect(second.duplicates, isNotEmpty);

      second.updateTransactionDate(DateTime(2026, 10, 2));
      await settle();

      expect(second.duplicates, isEmpty);
    });

    test('checkDuplicates dapat dipanggil ulang sebelum menyimpan', () async {
      final FakeTransactionRepository repo = FakeTransactionRepository();
      final ScanViewModel first = await readyScan(sampleReceipt, repo);
      await first.saveTransaction();

      final ScanViewModel second = await readyScan(sampleReceipt, repo);
      final List<DuplicateMatch> found = await second.checkDuplicates();

      expect(found, hasLength(1));
    });

    test('pemeriksaan yang gagal tidak menghalangi penyimpanan', () async {
      // Repository tiruan tanpa findSameDayAmount: pemeriksaan melempar galat.
      final _NoDuplicateSupport repo = _NoDuplicateSupport();
      final ScanViewModel scan = await readyScan(sampleReceipt, repo);
      await settle();

      expect(scan.duplicates, isEmpty);
      expect(await scan.saveTransaction(), isTrue);
    });
  });
}

class _NoDuplicateSupport extends FakeTransactionRepository {
  @override
  Future<List<TransactionModel>> findSameDayAmount(
    int userId,
    DateTime date,
    double total, {
    double tolerance = 1,
  }) {
    throw StateError('database tidak tersedia');
  }
}
