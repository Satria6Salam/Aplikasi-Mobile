import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/data/database/app_database.dart';
import 'package:smart_receipt/data/database/database_schema.dart';
import 'package:smart_receipt/data/models/purchase_record_model.dart';
import 'package:smart_receipt/data/models/transaction_filter.dart';
import 'package:smart_receipt/data/models/transaction_item_model.dart';
import 'package:smart_receipt/data/models/transaction_model.dart';
import 'package:smart_receipt/data/repositories/category_repository.dart';
import 'package:smart_receipt/data/repositories/transaction_repository.dart';
import 'package:smart_receipt/services/price_comparison_service.dart';
import 'package:smart_receipt/viewmodels/auth_viewmodel.dart';
import 'package:smart_receipt/viewmodels/price_comparison_viewmodel.dart';
import 'package:smart_receipt/viewmodels/search_viewmodel.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'viewmodels_test.dart' show buildLoggedInAuth;

/// AppDatabase tiruan yang memakai SQLite dalam memori (skema asli).
class _MemoryDatabase extends Fake implements AppDatabase {
  _MemoryDatabase(this.db);

  final Database db;

  @override
  Future<Database> get database async => db;
}

// Id kategori mengikuti urutan DatabaseSchema.defaultCategories.
const int catKonsumsi = 1;
const int catKesehatan = 3;
const int catBahanMakanan = 7;

Future<Database> openMemoryDatabase() async {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (Database db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (Database db, int version) async {
        for (final String statement in DatabaseSchema.createStatements) {
          await db.execute(statement);
        }
        for (final String statement in DatabaseSchema.createIndexes) {
          await db.execute(statement);
        }
        final String now = DateTime(2026, 1, 1).toIso8601String();
        for (final Map<String, String> c in DatabaseSchema.defaultCategories) {
          await db.insert('categories', <String, Object?>{
            'category_name': c['name'],
            'description': c['description'],
            'created_at': now,
          });
        }
      },
    ),
  );
}

Future<void> addUser(Database db, int id) =>
    db.insert('users', <String, Object?>{
      'user_id': id,
      'name': 'Pengguna $id',
      'email': 'u$id@mail.com',
      'password_hash': 'x',
      'created_at': '2026-01-01T00:00:00.000',
      'updated_at': '2026-01-01T00:00:00.000',
    });

/// Menyimpan transaksi beserta barangnya: (nama, harga satuan, kategori, jumlah).
Future<int> addTransaction(
  Database db, {
  required int userId,
  required String merchant,
  required DateTime date,
  required double total,
  int categoryId = catKonsumsi,
  String? notes,
  String? branch,
  String? address,
  List<(String, double, int, double)> items = const <(
    String,
    double,
    int,
    double
  )>[],
}) async {
  final DateTime now = DateTime(2026, 12, 1);
  final int id = await db.insert(
    'transactions',
    TransactionModel(
      userId: userId,
      merchantName: merchant,
      transactionDate: date,
      totalAmount: total,
      categoryId: categoryId,
      notes: notes,
      storeBranch: branch,
      storeAddress: address,
      createdAt: now,
      updatedAt: now,
    ).toMap(),
  );
  for (final (String name, double unit, int cat, double qty) in items) {
    await db.insert(
      'transaction_items',
      TransactionItemModel(
        transactionId: id,
        name: name,
        quantity: qty,
        unitPrice: unit,
        totalPrice: unit * qty,
        categoryId: cat,
        createdAt: now,
      ).toMap(),
    );
  }
  return id;
}

class Fixture {
  Fixture(this.db, this.repo, this.userId);

  final Database db;
  final TransactionRepository repo;
  final int userId;
  final Map<String, int> ids = <String, int>{};
}

/// Lima transaksi milik pengguna + satu milik pengguna lain.
Future<Fixture> buildFixture(int userId) async {
  final Database db = await openMemoryDatabase();
  await addUser(db, userId);
  await addUser(db, userId + 1);
  final Fixture f =
      Fixture(db, TransactionRepository(database: _MemoryDatabase(db)), userId);

  f.ids['t1'] = await addTransaction(
    db,
    userId: userId,
    merchant: 'Indomaret',
    date: DateTime(2026, 10, 1),
    total: 33000,
    branch: 'Urek Urek',
    address: 'Jalan Raya Urek Urek, Gondanglegi',
    items: <(String, double, int, double)>[
      ('Telur Ayam 1KG', 28000, catBahanMakanan, 1),
      ('Air Mineral', 5000, catKonsumsi, 1),
    ],
  );
  f.ids['t2'] = await addTransaction(
    db,
    userId: userId,
    merchant: 'Alfamart',
    date: DateTime(2026, 10, 10),
    total: 29000,
    items: <(String, double, int, double)>[
      ('TELUR AYAM 1 KG', 26000, catBahanMakanan, 1),
      ('Permen', 3000, catKonsumsi, 1),
    ],
  );
  f.ids['t3'] = await addTransaction(
    db,
    userId: userId,
    merchant: 'Indomaret',
    date: DateTime(2026, 11, 5),
    total: 30000,
    items: <(String, double, int, double)>[
      ('Telur Ayam 1kg', 30000, catBahanMakanan, 1),
    ],
  );
  f.ids['t4'] = await addTransaction(
    db,
    userId: userId,
    merchant: 'Apotek Sehat',
    date: DateTime(2026, 11, 6),
    total: 15000,
    categoryId: catKesehatan,
    notes: 'vitamin untuk ibu',
    items: <(String, double, int, double)>[
      ('Vitamin C', 15000, catKesehatan, 1),
    ],
  );
  f.ids['t5'] = await addTransaction(
    db,
    userId: userId,
    merchant: 'Alfamart',
    date: DateTime(2026, 11, 12),
    total: 27000,
    items: <(String, double, int, double)>[
      ('Telur Ayam 1kg', 27000, catBahanMakanan, 1),
    ],
  );
  // Milik pengguna lain: tidak boleh pernah muncul.
  await addTransaction(
    db,
    userId: userId + 1,
    merchant: 'Alfamart',
    date: DateTime(2026, 11, 13),
    total: 1000,
    items: <(String, double, int, double)>[
      ('Telur Ayam 1kg', 1000, catBahanMakanan, 1),
    ],
  );
  return f;
}

List<String> idsOf(Fixture f, List<TransactionModel> list) => <String>[
      for (final TransactionModel t in list)
        f.ids.entries
            .firstWhere((MapEntry<String, int> e) => e.value == t.id)
            .key,
    ];

/// Menunggu query SQLite (berjalan di isolate lain, jadi butuh waktu nyata)
/// dan pencarian berjenjang selesai.
Future<void> settle() async {
  for (int i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  for (int i = 0; i < 12; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('Pencarian transaksi (SQLite sungguhan)', () {
    late Fixture f;
    setUp(() async => f = await buildFixture(1));
    tearDown(() => f.db.close());

    Future<List<String>> run(TransactionFilter filter) async =>
        idsOf(f, await f.repo.searchTransactions(f.userId, filter));

    test('tanpa kriteria: semua transaksi pengguna, terbaru dulu', () async {
      expect(await run(const TransactionFilter()),
          <String>['t5', 't4', 't3', 't2', 't1']);
    });

    test('kata kunci mencari nama barang di semua periode', () async {
      expect(await run(const TransactionFilter(query: 'telur')),
          <String>['t5', 't3', 't2', 't1']);
      expect(await run(const TransactionFilter(query: 'TELUR')),
          <String>['t5', 't3', 't2', 't1'],
          reason: 'tidak peka huruf besar');
    });

    test('beberapa kata harus cocok semua (toko + barang)', () async {
      expect(await run(const TransactionFilter(query: 'telur alfamart')),
          <String>['t5', 't2']);
      expect(
          await run(const TransactionFilter(query: 'telur apotek')), isEmpty);
    });

    test('cocok dengan cabang, alamat, dan catatan', () async {
      expect(await run(const TransactionFilter(query: 'urek')), <String>['t1']);
      expect(await run(const TransactionFilter(query: 'gondanglegi')),
          <String>['t1']);
      expect(await run(const TransactionFilter(query: 'untuk ibu')),
          <String>['t4']);
    });

    test('karakter khusus LIKE dianggap huruf biasa', () async {
      expect(await run(const TransactionFilter(query: '%')), isEmpty);
      expect(await run(const TransactionFilter(query: '_')), isEmpty);
    });

    test('filter rentang tanggal (inklusif)', () async {
      expect(
        await run(TransactionFilter(from: DateTime(2026, 11, 5))),
        <String>['t5', 't4', 't3'],
      );
      expect(
        await run(TransactionFilter(
            from: DateTime(2026, 10, 10), to: DateTime(2026, 11, 5))),
        <String>['t3', 't2'],
      );
      expect(await run(TransactionFilter(to: DateTime(2026, 9, 30))), isEmpty);
    });

    test('filter rentang total struk', () async {
      expect(
        await run(const TransactionFilter(minTotal: 28000, maxTotal: 33000)),
        <String>['t3', 't2', 't1'],
      );
      expect(
          await run(const TransactionFilter(maxTotal: 15000)), <String>['t4']);
    });

    test('filter kategori memeriksa kategori utama DAN kategori barang',
        () async {
      // t1..t3, t5 berkategori utama Konsumsi tetapi memuat barang Bahan Makanan.
      expect(
        await run(const TransactionFilter(categoryIds: <int>{catBahanMakanan})),
        <String>['t5', 't3', 't2', 't1'],
      );
      expect(
        await run(const TransactionFilter(categoryIds: <int>{catKesehatan})),
        <String>['t4'],
      );
      expect(
        await run(const TransactionFilter(
            categoryIds: <int>{catKesehatan, catBahanMakanan})),
        hasLength(5),
      );
    });

    test('semua filter digabung (DAN)', () async {
      expect(
        await run(TransactionFilter(
          query: 'telur',
          from: DateTime(2026, 10, 5),
          maxTotal: 29000,
          categoryIds: const <int>{catBahanMakanan},
        )),
        <String>['t5', 't2'],
      );
    });

    test('pengurutan', () async {
      expect(
        await run(const TransactionFilter(sort: SearchSort.highest)),
        <String>['t1', 't3', 't2', 't5', 't4'],
      );
      expect(
        await run(const TransactionFilter(sort: SearchSort.lowest)),
        <String>['t4', 't5', 't2', 't3', 't1'],
      );
      expect(
        await run(const TransactionFilter(sort: SearchSort.oldest)),
        <String>['t1', 't2', 't3', 't4', 't5'],
      );
    });

    test('pencarian barang memuat toko, tanggal, dan harga satuan', () async {
      final List<PurchaseRecord> found = await f.repo
          .searchPurchases(f.userId, const TransactionFilter(query: 'telur'));

      expect(found.map((PurchaseRecord p) => p.merchantName),
          <String>['Alfamart', 'Indomaret', 'Alfamart', 'Indomaret']);
      expect(found.map((PurchaseRecord p) => p.unitPrice),
          <double>[27000, 30000, 26000, 28000]);
      expect(found.first.date, DateTime(2026, 11, 12));
      expect(found.last.storeBranch, 'Urek Urek');
      expect(found.first.categoryName, 'Bahan Makanan');
    });

    test('pencarian barang bisa digabung dengan nama toko', () async {
      final List<PurchaseRecord> found = await f.repo.searchPurchases(
          f.userId, const TransactionFilter(query: 'telur alfamart'));
      expect(found, hasLength(2));
      expect(found.every((PurchaseRecord p) => p.merchantName == 'Alfamart'),
          isTrue);
    });
  });

  group('PriceComparisonService', () {
    const PriceComparisonService service = PriceComparisonService();

    test('normalisasi menyeragamkan ukuran dan satuan', () {
      expect(PriceComparisonService.normalize('AQUA 600 ML'), 'aqua 600ml');
      expect(PriceComparisonService.normalize('Susu UHT 1,5 Ltr'),
          'susu uht 1.5l');
      expect(PriceComparisonService.normalize('Telur Ayam 1 KG'),
          'telur ayam 1kg');
      expect(PriceComparisonService.normalize('Kopi-Kapal Api (Sachet)'),
          'kopi kapal api sachet');
    });

    test('barang yang sama dikenali walau penulisan berbeda', () {
      bool same(String a, String b) => PriceComparisonService.sameProduct(
          PriceComparisonService.normalize(a),
          PriceComparisonService.normalize(b));

      expect(same('AQUA 600ML', 'Aqua 600 ml'), isTrue);
      expect(same('Telur Ayam 1KG', 'TELUR AYAM 1 KG'), isTrue);
      expect(same('Indomie Goreng', 'Indomie Gorang'), isTrue,
          reason: 'salah baca satu huruf');
    });

    test('ukuran atau varian berbeda dianggap produk lain', () {
      bool same(String a, String b) => PriceComparisonService.sameProduct(
          PriceComparisonService.normalize(a),
          PriceComparisonService.normalize(b));

      expect(same('AQUA 600ML', 'AQUA 1500ML'), isFalse);
      expect(same('Indomie Goreng', 'Indomie Goreng Rendang'), isFalse);
      expect(same('Teh Pucuk', 'Teh Botol'), isFalse);
    });

    List<PurchaseRecord> record(
      int id,
      String name,
      String store,
      DateTime date,
      double unit,
    ) =>
        <PurchaseRecord>[
          PurchaseRecord(
            itemId: id,
            transactionId: id,
            itemName: name,
            quantity: 1,
            unitPrice: unit,
            totalPrice: unit,
            categoryId: 1,
            categoryName: 'Bahan Makanan',
            merchantName: store,
            date: date,
          ),
        ];

    test('statistik per toko, penghematan, dan perubahan harga', () {
      final List<ProductPrices> products = service.compare(<PurchaseRecord>[
        ...record(
            1, 'Telur Ayam 1KG', 'Indomaret', DateTime(2026, 10, 1), 28000),
        ...record(
            2, 'TELUR AYAM 1 KG', 'Alfamart', DateTime(2026, 10, 10), 26000),
        ...record(
            3, 'Telur Ayam 1kg', 'Indomaret', DateTime(2026, 11, 5), 30000),
        ...record(
            4, 'Telur Ayam 1kg', 'Alfamart', DateTime(2026, 11, 12), 27000),
        ...record(5, 'Susu UHT 1L', 'Alfamart', DateTime(2026, 11, 1), 18000),
      ]);

      expect(products, hasLength(2));
      final ProductPrices telur = products.first;
      expect(telur.count, 4);
      expect(telur.storeCount, 2);
      expect(telur.name, 'Telur Ayam 1kg', reason: 'penulisan paling sering');
      expect(telur.lowest, 26000);
      expect(telur.highest, 30000);
      expect(telur.average, 27750);

      expect(telur.cheapestStore!.merchant, 'Alfamart');
      expect(telur.cheapestStore!.average, 26500);
      expect(telur.priciestStore!.merchant, 'Indomaret');
      expect(telur.priciestStore!.average, 29000);
      expect(telur.potentialSaving, closeTo(2500 / 29000, 1e-9));
      expect(telur.cheapestPurchase.merchantName, 'Alfamart');

      // Pembelian terakhir (Alfamart 27.000) vs sebelumnya di Alfamart (26.000).
      final PriceChange change = telur.latestChange!;
      expect(change.sameStore, isTrue);
      expect(change.previousPrice, 26000);
      expect(change.percent, closeTo(1000 / 26000, 1e-9));
      expect(change.trend, PriceTrend.up);

      expect(products.last.isComparable, isFalse);
      expect(products.last.latestChange, isNull);
    });

    test('kalimat ringkasan menyebut toko termurah dan perubahan harga', () {
      final List<ProductPrices> products = service.compare(<PurchaseRecord>[
        ...record(1, 'Telur', 'Indomaret', DateTime(2026, 10, 1), 29000),
        ...record(2, 'Telur', 'Alfamart', DateTime(2026, 10, 10), 26500),
        ...record(3, 'Telur', 'Alfamart', DateTime(2026, 11, 12), 24000),
      ]);

      final List<String> lines =
          service.insights(products.single, money: (double v) => 'Rp$v');

      expect(lines.first, contains('Termurah di Alfamart'));
      expect(lines.first, contains('lebih murah dari Indomaret'));
      expect(lines.any((String l) => l.contains('turun')), isTrue);
    });

    test('harga hampir sama di semua toko', () {
      final List<ProductPrices> products = service.compare(<PurchaseRecord>[
        ...record(1, 'Gula 1kg', 'Indomaret', DateTime(2026, 10, 1), 15000),
        ...record(2, 'Gula 1kg', 'Alfamart', DateTime(2026, 10, 2), 15100),
      ]);

      expect(
        service.insights(products.single, money: (double v) => '$v').first,
        'Harganya hampir sama di semua toko.',
      );
    });

    test('harga nol atau negatif diabaikan', () {
      final List<ProductPrices> products = service.compare(<PurchaseRecord>[
        ...record(1, 'Gratisan', 'Indomaret', DateTime(2026, 10, 1), 0),
        ...record(2, 'Roti', 'Indomaret', DateTime(2026, 10, 1), 5000),
      ]);
      expect(products.map((ProductPrices p) => p.name), <String>['Roti']);
    });
  });

  group('ViewModel', () {
    late Fixture f;
    late AuthViewModel auth;

    setUp(() async {
      auth = await buildLoggedInAuth();
      f = await buildFixture(auth.currentUser!.id!);
    });
    tearDown(() => f.db.close());

    SearchViewModel searchVm() => SearchViewModel(
          authViewModel: auth,
          transactionRepository: f.repo,
          categoryRepository:
              CategoryRepository(database: _MemoryDatabase(f.db)),
          debounce: Duration.zero,
        );

    test('SearchViewModel: memuat semua lalu menyaring saat mengetik',
        () async {
      final SearchViewModel vm = searchVm();
      await vm.load();

      expect(vm.results, hasLength(5));
      expect(vm.purchases, isEmpty,
          reason: 'tanpa kata kunci tidak ada daftar barang');
      expect(vm.categories, isNotEmpty);
      expect(vm.totalAmount, 33000 + 29000 + 30000 + 15000 + 27000);

      vm.setQuery('telur');
      await settle();

      expect(vm.results, hasLength(4));
      expect(vm.purchases, hasLength(4));
      final ItemSearchSummary summary = vm.itemSummary!;
      expect(summary.latest.merchantName, 'Alfamart');
      expect(summary.latest.unitPrice, 27000);
      expect(summary.cheapest.unitPrice, 26000);
      expect(summary.cheapest.merchantName, 'Alfamart');
      expect(summary.storeCount, 2);
      expect(summary.count, 4);
    });

    test('SearchViewModel: filter kategori, total, dan hapus semua', () async {
      final SearchViewModel vm = searchVm();
      await vm.load();

      vm.toggleCategory(catKesehatan);
      await settle();
      expect(vm.results, hasLength(1));
      expect(vm.filter.activeFilterCount, 1);
      expect(vm.categoryName(catKesehatan), 'Kesehatan');

      vm.toggleCategory(catKesehatan);
      await settle();
      expect(vm.results, hasLength(5));

      vm.setTotalRange(28000, null);
      vm.setDateRange(DateTime(2026, 10, 15), null);
      await settle();
      expect(vm.results.map((TransactionModel t) => t.totalAmount),
          <double>[30000]);
      expect(vm.filter.activeFilterCount, 2);

      vm.clearAll();
      await settle();
      expect(vm.results, hasLength(5));
      expect(vm.filter.isEmpty, isTrue);
    });

    test('SearchViewModel: hanya hasil pencarian terbaru yang dipakai',
        () async {
      final SearchViewModel vm = searchVm();
      await vm.load();

      // Dua pencarian beruntun: yang lama selesai belakangan tetapi diabaikan.
      vm.setSort(SearchSort.oldest);
      vm.setQuery('apotek');
      await settle();

      expect(vm.results, hasLength(1));
      expect(vm.filter.sort, SearchSort.oldest);
    });

    PriceComparisonViewModel priceVm() => PriceComparisonViewModel(
          authViewModel: auth,
          transactionRepository: f.repo,
        );

    test('PriceComparisonViewModel: mengelompokkan barang dari basis data',
        () async {
      final PriceComparisonViewModel vm = priceVm();
      await vm.load();

      expect(vm.errorMessage, isNull);
      final ProductPrices telur = vm.products.first;
      expect(telur.count, 4, reason: 'milik pengguna lain tidak ikut');
      expect(telur.storeCount, 2);
      expect(vm.comparableCount, 1);
      expect(vm.allProducts.map((ProductPrices p) => p.key),
          containsAll(<String>['telur ayam 1kg', 'vitamin c', 'air mineral']));
    });

    test('PriceComparisonViewModel: cari, filter, dan urutkan', () async {
      final PriceComparisonViewModel vm = priceVm();
      await vm.load();

      vm.setQuery('vit');
      expect(
          vm.products.map((ProductPrices p) => p.key), <String>['vitamin c']);

      vm.setQuery('');
      vm.setOnlyComparable(true);
      expect(vm.products, hasLength(1));
      expect(vm.products.single.key, 'telur ayam 1kg');

      vm.setOnlyComparable(false);
      vm.setSort(ProductSort.biggestSaving);
      expect(vm.products.first.key, 'telur ayam 1kg');
      vm.setSort(ProductSort.name);
      expect(vm.products.first.name, 'Air Mineral');
    });

    test('PriceComparisonViewModel: bestMatch dari nama barang hasil pencarian',
        () async {
      final PriceComparisonViewModel vm = priceVm();
      await vm.load();

      expect(vm.bestMatch('TELUR AYAM 1 KG')!.key, 'telur ayam 1kg');
      expect(vm.bestMatch('telur')!.key, 'telur ayam 1kg');
      expect(vm.bestMatch('sepatu'), isNull);
    });
  });
}
