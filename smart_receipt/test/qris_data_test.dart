import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/core/constants/db_constants.dart';
import 'package:smart_receipt/data/database/database_schema.dart';
import 'package:smart_receipt/data/models/ml_classification_model.dart';
import 'package:smart_receipt/data/models/ocr_result_model.dart';
import 'package:smart_receipt/data/models/parsed_receipt_model.dart';
import 'package:smart_receipt/data/models/qris_pending_model.dart';
import 'package:smart_receipt/data/models/tfidf_feature_model.dart';
import 'package:smart_receipt/data/models/transaction_item_model.dart';
import 'package:smart_receipt/data/models/transaction_model.dart';
import 'package:smart_receipt/data/repositories/qris_pending_repository.dart';
import 'package:smart_receipt/data/repositories/transaction_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/memory_database.dart';

final DateTime now = DateTime(2026, 11, 23, 17);

TransactionModel qrisTx({
  double total = 41000,
  String merchant = 'Wizzmie Muharto',
  String merchantId = 'ID1020099887766',
  int categoryId = 1,
  int userId = 1,
  double? lat,
  double? lng,
  String? branch,
}) =>
    TransactionModel(
      userId: userId,
      merchantName: merchant,
      transactionDate: DateTime(2026, 11, 23),
      totalAmount: total,
      categoryId: categoryId,
      notes: 'QRIS',
      createdAt: now,
      updatedAt: now,
      source: TransactionSource.qris,
      merchantId: merchantId,
      latitude: lat,
      longitude: lng,
      locationSource: lat == null ? null : 'gps',
      storeBranch: branch,
    );

void main() {
  setUpAll(sqfliteFfiInit);

  group('Migrasi basis data v8 -> v9', () {
    test('kolom dan tabel baru ditambahkan, data lama utuh', () async {
      final Database db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (Database d) => d.execute('PRAGMA foreign_keys = ON'),
          onCreate: (Database d, int v) async {
            // Skema versi 8: tanpa tabel qris_pending dan tanpa dua kolom baru.
            for (final String sql in DatabaseSchema.createStatements) {
              if (sql.contains('CREATE TABLE qris_pending')) continue;
              await d.execute(
                sql
                    .replaceAll('  source TEXT,\n', '')
                    .replaceAll('  merchant_id TEXT,\n', ''),
              );
            }
          },
        ),
      );
      await addUser(db, 1);
      await db.insert('categories', <String, Object?>{
        'category_name': 'Konsumsi',
        'created_at': now.toIso8601String(),
      });
      // Baris lama (skema v8) dimasukkan tanpa kolom baru.
      final int oldId = await db.insert('transactions', <String, Object?>{
        'user_id': 1,
        'merchant_name': 'Toko Lama',
        'transaction_date': '2026-10-01',
        'total_amount': 5000.0,
        'category_id': 1,
        'is_manual_edit': 0,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      final List<Map<String, Object?>> before =
          await db.rawQuery('PRAGMA table_info(transactions)');
      expect(before.map((Map<String, Object?> c) => c['name']),
          isNot(contains('merchant_id')));

      for (final String statement in DatabaseSchema.upgradeToV9) {
        await db.execute(statement);
      }

      final List<Map<String, Object?>> after =
          await db.rawQuery('PRAGMA table_info(transactions)');
      expect(after.map((Map<String, Object?> c) => c['name']),
          containsAll(<String>['source', 'merchant_id']));
      final List<Map<String, Object?>> old = await db.query('transactions',
          where: 'transaction_id = ?', whereArgs: <Object?>[oldId]);
      expect(old.single['total_amount'], 5000, reason: 'data lama utuh');
      expect(old.single['source'], isNull);

      final QrisPendingRepository repo =
          QrisPendingRepository(database: MemoryDatabase(db));
      await repo.insert(QrisPendingModel(
        userId: 1,
        merchantName: 'Warung',
        scannedAt: now,
      ));
      expect(await repo.count(1), 1);
      await db.close();
    });
  });

  group('Transaksi QRIS dan struk (SQLite sungguhan)', () {
    late dynamic db;
    late TransactionRepository repo;
    late QrisPendingRepository pending;

    setUp(() async {
      db = await openMemoryDatabase();
      await addUser(db, 1);
      await addUser(db, 2);
      final MemoryDatabase mem = MemoryDatabase(db);
      repo = TransactionRepository(database: mem);
      pending = QrisPendingRepository(database: mem);
    });
    tearDown(() => db.close());

    test('transaksi menyimpan sumber QRIS dan NMID', () async {
      final TransactionModel saved = await repo.insert(qrisTx());

      final TransactionModel? loaded = await repo.getById(saved.id!);
      expect(loaded!.isQris, isTrue);
      expect(loaded.source, TransactionSource.qris);
      expect(loaded.merchantId, 'ID1020099887766');
    });

    test('kategori terakhir untuk NMID diingat, per pengguna', () async {
      await repo.insert(qrisTx(categoryId: 1));
      final TransactionModel later = qrisTx(categoryId: 4).copyWith();
      await repo.insert(TransactionModel(
        userId: 1,
        merchantName: later.merchantName,
        transactionDate: DateTime(2026, 11, 24),
        totalAmount: 30000,
        categoryId: 4,
        createdAt: now,
        updatedAt: now,
        source: TransactionSource.qris,
        merchantId: 'ID1020099887766',
      ));
      await repo.insert(qrisTx(categoryId: 6, userId: 2));

      expect(await repo.findCategoryByMerchantId(1, 'ID1020099887766'), 4,
          reason: 'koreksi terbaru yang dipakai');
      expect(await repo.findCategoryByMerchantId(1, 'ID000'), isNull);
      expect(await repo.findCategoryByMerchantId(2, 'ID1020099887766'), 6);
    });

    test('QRIS menunggu struk: simpan, daftar terbaru dulu, hitung, hapus',
        () async {
      final QrisPendingModel a = await pending.insert(QrisPendingModel(
        userId: 1,
        merchantName: 'Warung Bu Siti',
        city: 'Malang',
        merchantId: 'ID1',
        mcc: '5812',
        categoryId: 1,
        latitude: -7.97,
        longitude: 112.63,
        locationSource: 'gps',
        scannedAt: DateTime(2026, 11, 23, 10),
      ));
      await pending.insert(QrisPendingModel(
        userId: 1,
        merchantName: 'Toko B',
        scannedAt: DateTime(2026, 11, 23, 12),
      ));
      await pending.insert(QrisPendingModel(
        userId: 2,
        merchantName: 'Milik orang lain',
        scannedAt: now,
      ));

      final List<QrisPendingModel> list = await pending.getAll(1);
      expect(list.map((QrisPendingModel p) => p.merchantName),
          <String>['Toko B', 'Warung Bu Siti']);
      expect(await pending.count(1), 2);
      expect(list.last.hasLocation, isTrue);
      expect(list.last.city, 'Malang');

      expect((await pending.getById(a.id!))!.mcc, '5812');
      await pending.delete(a.id!);
      expect(await pending.getById(a.id!), isNull);
      expect(await pending.count(1), 1);
    });

    test('QRIS menunggu tidak dihitung sebagai pengeluaran', () async {
      await pending.insert(QrisPendingModel(
        userId: 1,
        merchantName: 'Warung',
        scannedAt: now,
      ));
      await repo.insert(qrisTx(total: 41000));

      expect(
        await repo.getTotalBetween(1, DateTime(2026, 11), DateTime(2026, 12)),
        41000,
      );
    });

    test('struk melengkapi transaksi QRIS: barang masuk, data QRIS tetap',
        () async {
      final TransactionModel qris = await repo.insert(qrisTx(
        lat: -7.97,
        lng: 112.63,
      ));

      await repo.completeWithScan(
        transactionId: qris.id!,
        ocr: OcrResultModel(
          userId: 1,
          imagePath: '/tmp/struk.jpg',
          rawText: 'WIZZMIE ...',
          ocrSource: OcrSource.camera,
          ocrStatus: OcrStatus.success,
          createdAt: now,
        ),
        parsed: ParsedReceiptModel(
          ocrId: 0,
          merchantName: 'Wizzmie',
          totalAmount: 41000,
          parsingStatus: ParsingStatus.success,
          createdAt: now,
        ),
        classification: MlClassificationModel(
          parsedId: 0,
          inputText: 'ice tea',
          preprocessedText: 'ice tea',
          predictionProbability: 0.9,
          modelName: 'nb',
          modelVersion: '1',
          classificationStatus: ClassificationStatus.success,
          createdAt: now,
        ),
        features: <TfidfFeatureModel>[
          const TfidfFeatureModel(
            classificationId: 0,
            term: 'ice',
            tf: 1,
            idf: 1,
            tfidfWeight: 1,
          ),
        ],
        items: <TransactionItemModel>[
          TransactionItemModel(
            transactionId: 0,
            name: 'Ice Tea',
            quantity: 2,
            unitPrice: 6818,
            totalPrice: 13636,
            categoryId: 1,
            createdAt: now,
          ),
          TransactionItemModel(
            transactionId: 0,
            name: 'Mie Disko Lv 1',
            quantity: 2,
            unitPrice: 11863,
            totalPrice: 23726,
            categoryId: 1,
            createdAt: now,
          ),
        ],
        categoryId: 1,
        storeBranch: 'Muharto',
        storeAddress: 'Jalan Muharto, Malang',
      );

      final TransactionModel done = (await repo.getById(qris.id!))!;
      expect(done.ocrId, isNotNull);
      expect(done.parsedId, isNotNull);
      expect(done.classificationId, isNotNull);
      expect(done.merchantName, 'Wizzmie Muharto', reason: 'nama QRIS tetap');
      expect(done.totalAmount, 41000);
      expect(done.notes, 'QRIS');
      expect(done.isQris, isTrue);
      expect(done.merchantId, 'ID1020099887766');
      expect(done.latitude, -7.97,
          reason: 'titik GPS saat scan QRIS dipertahankan');
      expect(done.storeBranch, 'Muharto',
          reason: 'diisi karena sebelumnya kosong');
      expect(done.storeAddress, 'Jalan Muharto, Malang');

      final items = await repo.getItems(qris.id!);
      expect(items.map((TransactionItemModel i) => i.name),
          <String>['Ice Tea', 'Mie Disko Lv 1']);
      expect(items.fold<double>(0, (double s, i) => s + i.totalPrice), 37362);
    });

    test('struk tidak menimpa cabang yang sudah ada', () async {
      final TransactionModel qris =
          await repo.insert(qrisTx(branch: 'Cabang Dinoyo'));

      await repo.completeWithScan(
        transactionId: qris.id!,
        ocr: OcrResultModel(
          userId: 1,
          imagePath: '/tmp/a.jpg',
          rawText: 'x',
          ocrSource: OcrSource.camera,
          ocrStatus: OcrStatus.success,
          createdAt: now,
        ),
        parsed: ParsedReceiptModel(
          ocrId: 0,
          parsingStatus: ParsingStatus.partial,
          createdAt: now,
        ),
        classification: MlClassificationModel(
          parsedId: 0,
          inputText: 'x',
          preprocessedText: 'x',
          modelName: 'nb',
          modelVersion: '1',
          classificationStatus: ClassificationStatus.success,
          createdAt: now,
        ),
        features: const <TfidfFeatureModel>[],
        items: const <TransactionItemModel>[],
        categoryId: 1,
        storeBranch: 'Muharto',
      );

      expect((await repo.getById(qris.id!))!.storeBranch, 'Cabang Dinoyo');
    });
  });
}
