import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/core/constants/db_constants.dart';
import 'package:smart_receipt/data/models/qris_pending_model.dart';
import 'package:smart_receipt/data/models/transaction_model.dart';
import 'package:smart_receipt/services/geocoding_service.dart';
import 'package:smart_receipt/services/mcc_categories.dart';
import 'package:smart_receipt/viewmodels/auth_viewmodel.dart';
import 'package:smart_receipt/viewmodels/qris_pending_viewmodel.dart';
import 'package:smart_receipt/viewmodels/qris_viewmodel.dart';

import 'helpers/fake_qris.dart';
import 'qris_parser_test.dart' show dynamicQris, nested, staticQris;
import 'viewmodels_test.dart' show FakeCategoryRepository, buildLoggedInAuth;

// Urutan id kategori pada FakeCategoryRepository: Konsumsi=1, Transportasi=2,
// Kesehatan=3, Belanja=4, Lainnya=5, Elektronik=6, Bahan Makanan=7, ...
const int idKonsumsi = 1;
const int idBelanja = 4;
const int idBahanMakanan = 7;

Future<void> settle() async {
  for (int i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late AuthViewModel auth;
  late QrisTransactionRepository txRepo;
  late FakeQrisPendingRepository pendingRepo;
  late FakeQrisLocationService location;
  int saved = 0;

  setUp(() async {
    auth = await buildLoggedInAuth();
    txRepo = QrisTransactionRepository();
    pendingRepo = FakeQrisPendingRepository();
    location = FakeQrisLocationService(result: sampleLocation());
    saved = 0;
  });

  QrisViewModel vm({bool withLocation = true}) => QrisViewModel(
        authViewModel: auth,
        transactionRepository: txRepo,
        categoryRepository: FakeCategoryRepository(),
        pendingRepository: pendingRepo,
        storeLocationService: withLocation ? location : null,
        onSaved: () => saved++,
        clock: () => DateTime(2026, 11, 23, 17),
      );

  group('Pemindaian', () {
    test('QRIS statis: toko terisi, nominal kosong, kategori dari jenis usaha',
        () async {
      final QrisViewModel q = vm();

      expect(await q.onScanned(staticQris()), isTrue);
      await settle();

      expect(q.hasData, isTrue);
      expect(q.data!.merchantName, 'Warung Bu Siti');
      expect(q.needsAmount, isTrue);
      expect(q.amount, isNull);
      expect(q.categoryId, idKonsumsi, reason: 'MCC 5812 = restoran');
      expect(q.suggestion, CategorySuggestion.businessType);
      expect(q.categoryName, 'Konsumsi');
      expect(q.date, DateTime(2026, 11, 23));
    });

    test('QRIS dinamis: nominal terisi dan tidak perlu diketik', () async {
      final QrisViewModel q = vm();

      await q.onScanned(dynamicQris());

      expect(q.needsAmount, isFalse);
      expect(q.amount, 41000);
      expect(q.data!.isDynamic, isTrue);
    });

    test('QRIS dinamis dengan biaya layanan: total sudah termasuk biaya',
        () async {
      final QrisViewModel q = vm();

      await q.onScanned(
          dynamicQris(extra: <String, String>{'55': '02', '56': '2500'}));

      expect(q.amount, 43500);
    });

    test('koreksi kategori sebelumnya untuk toko (NMID) lebih dipercaya',
        () async {
      txRepo.categoryByMerchantId['ID1020012345678'] = idBelanja;
      final QrisViewModel q = vm();

      await q.onScanned(staticQris());

      expect(q.categoryId, idBelanja, reason: 'bukan Konsumsi dari MCC');
      expect(q.suggestion, CategorySuggestion.history);
    });

    test('kode bukan QRIS: pesan galat, formulir tidak terbuka', () async {
      final QrisViewModel q = vm();

      expect(await q.onScanned('https://example.com/menu'), isFalse);

      expect(q.hasData, isFalse);
      expect(q.scanError, contains('bukan kode QRIS'));
    });

    test('kode rusak yang sama dibaca berulang tidak memproses ulang',
        () async {
      final QrisViewModel q = vm();
      final String tampered = staticQris().replaceFirst('BU SITI', 'BU SITA');
      int notifications = 0;
      q.addListener(() => notifications++);

      await q.onScanned(tampered);
      final int after1 = notifications;
      await q.onScanned(tampered);
      await q.onScanned(tampered);

      expect(q.scanError, contains('tidak valid'));
      expect(notifications, after1, reason: 'kamera memindai ulang tanpa efek');
    });

    test('kode valid setelah kode rusak menghapus pesan galat', () async {
      final QrisViewModel q = vm();
      await q.onScanned('bukan qris');
      expect(q.scanError, isNotNull);

      await q.onScanned(staticQris());

      expect(q.scanError, isNull);
      expect(q.hasData, isTrue);
    });

    test('kode kedua diabaikan selama formulir terbuka', () async {
      final QrisViewModel q = vm();
      await q.onScanned(staticQris(name: 'TOKO A'));

      expect(await q.onScanned(staticQris(name: 'TOKO B')), isFalse);

      expect(q.data!.merchantName, 'Toko A');
    });

    test('reset kembali ke pemindai', () async {
      final QrisViewModel q = vm();
      await q.onScanned(staticQris());

      q.reset();

      expect(q.hasData, isFalse);
      expect(q.amount, isNull);
      expect(await q.onScanned(staticQris(name: 'TOKO B')), isTrue);
      expect(q.data!.merchantName, 'Toko B');
    });
  });

  group('Menyimpan transaksi', () {
    test('QRIS statis: nominal diketik, tersimpan sebagai transaksi QRIS',
        () async {
      final QrisViewModel q = vm();
      await q.onScanned(staticQris(storeLabel: 'CABANG DINOYO'));
      await settle();

      q.setAmount(35000);
      q.setNotes('  makan siang  ');
      final QrisSaveResult? result = await q.save();

      expect(result, isNotNull);
      expect(result!.isPending, isFalse);
      final TransactionModel t = result.transaction!;
      expect(t.merchantName, 'Warung Bu Siti');
      expect(t.totalAmount, 35000);
      expect(t.categoryId, idKonsumsi);
      expect(t.source, TransactionSource.qris);
      expect(t.isQris, isTrue);
      expect(t.merchantId, 'ID1020012345678');
      expect(t.storeBranch, 'Cabang Dinoyo');
      expect(t.storeAddress, 'Malang');
      expect(t.notes, 'makan siang');
      expect(t.transactionDate, DateTime(2026, 11, 23));
      expect(t.isManualEdit, isFalse, reason: 'kategori tidak diubah');
      expect(txRepo.stored.single.id, t.id);
      expect(saved, 1);
    });

    test('lokasi: GPS dipakai, tersimpan pada transaksi, dan diingat per NMID',
        () async {
      final QrisViewModel q = vm();
      await q.onScanned(staticQris());
      await settle();
      expect(q.locationStatus, QrisLocationStatus.found);
      expect(location.gpsFlags.single, isTrue,
          reason: 'memindai QRIS terjadi di toko');
      expect(location.cacheKeys.single, 'qris:ID1020012345678');

      q.setAmount(20000);
      final QrisSaveResult? result = await q.save();

      final TransactionModel t = result!.transaction!;
      expect(t.latitude, closeTo(-7.9667, 1e-6));
      expect(t.locationSource, LocationSource.nearby);
      expect(location.rememberedAddresses.single, 'qris:ID1020012345678');
    });

    test('lokasi tidak ditemukan tidak menghalangi penyimpanan', () async {
      location.result = null;
      final QrisViewModel q = vm();
      await q.onScanned(staticQris());
      await settle();
      expect(q.locationStatus, QrisLocationStatus.notFound);

      q.setAmount(20000);
      final QrisSaveResult? result = await q.save();

      expect(result!.transaction!.latitude, isNull);
    });

    test('tanpa layanan lokasi tetap bisa disimpan', () async {
      final QrisViewModel q = vm(withLocation: false);
      await q.onScanned(staticQris());
      q.setAmount(20000);

      expect((await q.save())!.transaction, isNotNull);
      expect(q.locationStatus, QrisLocationStatus.idle);
    });

    test('QRIS dinamis langsung bisa disimpan tanpa mengetik', () async {
      final QrisViewModel q = vm();
      await q.onScanned(dynamicQris());

      final QrisSaveResult? result = await q.save();

      expect(result!.transaction!.totalAmount, 41000);
      expect(result.transaction!.merchantName, 'Wizzmie Muharto');
    });

    test('kategori diubah pengguna: ditandai disunting', () async {
      final QrisViewModel q = vm();
      await q.onScanned(staticQris());
      await settle();
      q.selectCategory(idBahanMakanan);
      q.setAmount(20000);

      final QrisSaveResult? result = await q.save();

      expect(result!.transaction!.categoryId, idBahanMakanan);
      expect(result.transaction!.isManualEdit, isTrue);
    });

    test('nominal kosong atau nol ditolak dengan pesan jelas', () async {
      final QrisViewModel q = vm();
      await q.onScanned(staticQris());
      await settle();

      expect(await q.save(), isNull);
      expect(q.formError, 'Isi jumlah yang Anda bayarkan');

      q.setAmount(0);
      expect(await q.save(), isNull);
      expect(txRepo.stored, isEmpty);
      expect(saved, 0);
    });

    test('nominal terlalu besar ditolak', () async {
      final QrisViewModel q = vm();
      await q.onScanned(staticQris());
      await settle();
      q.setAmount(2e12);

      expect(await q.save(), isNull);
      expect(q.formError, 'Jumlah terlalu besar');
    });

    test('tanggal bisa diubah', () async {
      final QrisViewModel q = vm();
      await q.onScanned(staticQris());
      await settle();
      q.setDate(DateTime(2026, 11, 20, 9));
      q.setAmount(20000);

      expect((await q.save())!.transaction!.transactionDate,
          DateTime(2026, 11, 20));
    });
  });

  group('Menunggu struk', () {
    test(
        'QRIS statis tanpa nominal: disimpan sebagai menunggu, bukan transaksi',
        () async {
      final QrisViewModel q = vm();
      await q.onScanned(staticQris());
      await settle();

      q.setWaitForReceipt(true);
      expect(q.waitForReceipt, isTrue);
      final QrisSaveResult? result = await q.save();

      expect(result!.isPending, isTrue);
      expect(txRepo.stored, isEmpty, reason: 'belum jadi pengeluaran');
      final QrisPendingModel p = pendingRepo.items.single;
      expect(p.merchantName, 'Warung Bu Siti');
      expect(p.city, 'Malang');
      expect(p.merchantId, 'ID1020012345678');
      expect(p.mcc, '5812');
      expect(p.categoryId, idKonsumsi);
      expect(p.hasLocation, isTrue, reason: 'titik GPS saat memindai disimpan');
      expect(saved, 1);
    });

    test('QRIS dinamis tidak bisa menunggu struk (nominalnya sudah ada)',
        () async {
      final QrisViewModel q = vm();
      await q.onScanned(dynamicQris());

      q.setWaitForReceipt(true);

      expect(q.waitForReceipt, isFalse);
      expect((await q.save())!.isPending, isFalse);
    });

    test('menunggu struk tidak butuh nominal', () async {
      final QrisViewModel q = vm();
      await q.onScanned(staticQris());
      await settle();
      q.setWaitForReceipt(true);

      expect(await q.save(), isNotNull);
      expect(q.formError, isNull);
    });
  });

  group('Transaksi ganda', () {
    TransactionModel existing(
            {String merchant = 'Warung Bu Siti', double total = 35000}) =>
        TransactionModel(
          id: 1,
          userId: auth.currentUser!.id!,
          merchantName: merchant,
          transactionDate: DateTime(2026, 11, 23),
          totalAmount: total,
          categoryId: idKonsumsi,
          createdAt: DateTime(2026, 11, 23),
          updatedAt: DateTime(2026, 11, 23),
          source: TransactionSource.qris,
        );

    test('QRIS yang sama dicatat dua kali: peringatan muncul', () async {
      txRepo.stored.add(existing());
      final QrisViewModel q = vm();
      await q.onScanned(staticQris());
      await settle();

      q.setAmount(35000);
      await settle();

      expect(q.duplicates, hasLength(1));
      expect(q.duplicates.first.transaction.merchantName, 'Warung Bu Siti');
    });

    test('nominal berbeda: tidak dianggap ganda', () async {
      txRepo.stored.add(existing());
      final QrisViewModel q = vm();
      await q.onScanned(staticQris());
      await settle();

      q.setAmount(36000);
      await settle();

      expect(q.duplicates, isEmpty);
    });

    test('QRIS dinamis langsung memeriksa duplikat', () async {
      txRepo.stored.add(existing(merchant: 'Wizzmie Muharto', total: 41000));
      final QrisViewModel q = vm();

      await q.onScanned(dynamicQris());
      await settle();

      expect(q.duplicates, hasLength(1));
    });
  });

  group('QrisPendingViewModel', () {
    late QrisPendingViewModel pv;
    int changed = 0;

    QrisPendingModel pending(
            {int? categoryId = idKonsumsi, double? lat = -7.97}) =>
        QrisPendingModel(
          userId: auth.currentUser!.id!,
          merchantName: 'Wizzmie Muharto',
          city: 'Malang',
          merchantId: 'ID1020099887766',
          mcc: '5812',
          categoryId: categoryId,
          latitude: lat,
          longitude: lat == null ? null : 112.63,
          locationSource: 'gps',
          scannedAt: DateTime(2026, 11, 23, 16),
        );

    setUp(() {
      changed = 0;
      pv = QrisPendingViewModel(
        authViewModel: auth,
        pendingRepository: pendingRepo,
        transactionRepository: txRepo,
        categoryRepository: FakeCategoryRepository(),
        onChanged: () => changed++,
        clock: () => DateTime(2026, 11, 23, 17),
      );
    });

    test('memuat daftar, terbaru dulu', () async {
      await pendingRepo.insert(pending());
      await pendingRepo.insert(QrisPendingModel(
        userId: auth.currentUser!.id!,
        merchantName: 'Warung Baru',
        scannedAt: DateTime(2026, 11, 23, 18),
      ));

      await pv.load();

      expect(pv.items.map((QrisPendingModel p) => p.merchantName),
          <String>['Warung Baru', 'Wizzmie Muharto']);
    });

    test('isi nominal sendiri: jadi transaksi QRIS dan hilang dari daftar',
        () async {
      final QrisPendingModel p = await pendingRepo.insert(pending());
      await pv.load();

      final TransactionModel? t = await pv.completeWithAmount(
        p,
        amount: 41000,
        date: DateTime(2026, 11, 23, 14),
      );

      expect(t, isNotNull);
      expect(t!.merchantName, 'Wizzmie Muharto');
      expect(t.totalAmount, 41000);
      expect(t.source, TransactionSource.qris);
      expect(t.merchantId, 'ID1020099887766');
      expect(t.categoryId, idKonsumsi);
      expect(t.latitude, -7.97);
      expect(t.transactionDate, DateTime(2026, 11, 23));
      expect(pv.items, isEmpty);
      expect(pendingRepo.items, isEmpty);
      expect(changed, 1);
    });

    test('kategori yang sudah dihapus: memakai "Lainnya"', () async {
      final QrisPendingModel p =
          await pendingRepo.insert(pending(categoryId: 999));
      await pv.load();

      final TransactionModel? t = await pv.completeWithAmount(p, amount: 5000);

      expect(t!.categoryId, 5, reason: 'Lainnya');
    });

    test('nominal tidak valid ditolak dan catatan tetap ada', () async {
      final QrisPendingModel p = await pendingRepo.insert(pending());
      await pv.load();

      expect(await pv.completeWithAmount(p, amount: 0), isNull);
      expect(pv.errorMessage, 'Jumlah harus lebih dari 0');
      expect(await pv.completeWithAmount(p, amount: 2e12), isNull);
      expect(pendingRepo.items, hasLength(1));
      expect(txRepo.stored, isEmpty);
    });

    test('menghapus catatan menunggu', () async {
      final QrisPendingModel p = await pendingRepo.insert(pending());
      await pv.load();

      expect(await pv.delete(p), isTrue);

      expect(pv.items, isEmpty);
      expect(changed, 1);
    });
  });

  group('MCC yang dipakai ViewModel selaras dengan kategori bawaan', () {
    test('nama kategori hasil MCC ada di FakeCategoryRepository', () async {
      final names =
          (await FakeCategoryRepository().getAll()).map((c) => c.name).toSet();
      for (final String mcc in <String>[
        '5812',
        '5411',
        '5541',
        '5912',
        '9999'
      ]) {
        expect(names, contains(MccCategories.of(mcc)), reason: mcc);
      }
      expect(nested(<String, String>{'00': 'A'}), '0001A');
    });
  });
}
