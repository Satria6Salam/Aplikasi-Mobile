import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_receipt/core/theme/app_theme.dart';
import 'package:smart_receipt/data/models/purchase_record_model.dart';
import 'package:smart_receipt/data/models/transaction_filter.dart';
import 'package:smart_receipt/data/models/transaction_model.dart';
import 'package:smart_receipt/data/repositories/category_repository.dart';
import 'package:smart_receipt/data/repositories/transaction_repository.dart';
import 'package:smart_receipt/viewmodels/auth_viewmodel.dart';
import 'package:smart_receipt/views/price/price_comparison_screen.dart';
import 'package:smart_receipt/views/search/search_screen.dart';

import 'viewmodels_test.dart' show FakeCategoryRepository, buildLoggedInAuth;

/// Repository tiruan: menerapkan kata kunci sederhana pada data tetap.
class FakeSearchRepository extends Fake implements TransactionRepository {
  final DateTime now = DateTime(2026, 11, 20);

  late final List<TransactionModel> all = <TransactionModel>[
    _tx(1, 'Alfamart', DateTime(2026, 11, 12), 27000),
    _tx(2, 'Apotek Sehat', DateTime(2026, 11, 6), 15000),
    _tx(3, 'Indomaret', DateTime(2026, 11, 5), 30000),
    _tx(4, 'Alfamart', DateTime(2026, 10, 10), 29000),
    _tx(5, 'Indomaret', DateTime(2026, 10, 1), 33000),
  ];

  TransactionModel _tx(int id, String merchant, DateTime date, double total) =>
      TransactionModel(
        id: id,
        userId: 1,
        merchantName: merchant,
        transactionDate: date,
        totalAmount: total,
        categoryId: 1,
        categoryName: 'Konsumsi',
        createdAt: now,
        updatedAt: now,
      );

  PurchaseRecord _p(
          int id, String name, String store, DateTime d, double unit) =>
      PurchaseRecord(
        itemId: id,
        transactionId: id,
        itemName: name,
        quantity: 1,
        unitPrice: unit,
        totalPrice: unit,
        categoryId: 7,
        categoryName: 'Bahan Makanan',
        merchantName: store,
        date: d,
      );

  late final List<PurchaseRecord> purchases = <PurchaseRecord>[
    _p(5, 'Telur Ayam 1kg', 'Alfamart', DateTime(2026, 11, 12), 27000),
    _p(4, 'Telur Ayam 1kg', 'Indomaret', DateTime(2026, 11, 5), 30000),
    _p(3, 'TELUR AYAM 1 KG', 'Alfamart', DateTime(2026, 10, 10), 26000),
    _p(2, 'Telur Ayam 1KG', 'Indomaret', DateTime(2026, 10, 1), 28000),
    _p(1, 'Vitamin C', 'Apotek Sehat', DateTime(2026, 11, 6), 15000),
  ];

  final List<TransactionFilter> seen = <TransactionFilter>[];

  @override
  Future<List<TransactionModel>> searchTransactions(
    int userId,
    TransactionFilter filter, {
    int limit = 300,
  }) async {
    seen.add(filter);
    return all.where((TransactionModel t) {
      for (final String token in filter.tokens) {
        if (!t.merchantName.toLowerCase().contains(token.toLowerCase())) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  @override
  Future<List<PurchaseRecord>> searchPurchases(
    int userId,
    TransactionFilter filter, {
    int limit = 500,
  }) async {
    return purchases.where((PurchaseRecord p) {
      for (final String token in filter.tokens) {
        if (!p.itemName.toLowerCase().contains(token.toLowerCase())) {
          return false;
        }
      }
      return true;
    }).toList();
  }
}

Future<void> pumpApp(
  WidgetTester tester, {
  required FakeSearchRepository repo,
  required Widget home,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 2.0; // 450 x 900 dp, mirip HP.
  addTearDown(tester.view.reset);

  final AuthViewModel auth =
      await tester.runAsync(buildLoggedInAuth) as AuthViewModel;

  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (BuildContext _, GoRouterState __) => home),
      GoRoute(
        path: '/price-compare',
        builder: (BuildContext _, GoRouterState state) =>
            PriceComparisonScreen(initialQuery: state.extra as String?),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: <Provider<dynamic>>[
        Provider<TransactionRepository>.value(value: repo),
        Provider<CategoryRepository>.value(value: FakeCategoryRepository()),
      ],
      child: ChangeNotifierProvider<AuthViewModel>.value(
        value: auth,
        child: MaterialApp.router(
          theme: AppTheme.light,
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

/// Beri waktu jeda pencarian (debounce) lalu gambar ulang.
Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  group('Layar Pencarian Lanjutan', () {
    testWidgets('menampilkan semua transaksi dan tombol filter',
        (tester) async {
      final FakeSearchRepository repo = FakeSearchRepository();
      await pumpApp(tester, repo: repo, home: const SearchScreen());

      expect(find.text('Pencarian Lanjutan'), findsOneWidget);
      expect(find.text('5 transaksi'), findsOneWidget);
      expect(find.text('Tanggal'), findsOneWidget);
      expect(find.text('Total struk'), findsOneWidget);
      expect(find.text('Kategori'), findsOneWidget);
      expect(find.byTooltip('Urutkan: Terbaru'), findsOneWidget);
      expect(find.text('Apotek Sehat'), findsOneWidget);
    });

    testWidgets('mengetik nama barang memunculkan kartu "Barang cocok"',
        (tester) async {
      final FakeSearchRepository repo = FakeSearchRepository();
      await pumpApp(tester, repo: repo, home: const SearchScreen());

      await tester.enterText(find.byType(TextField), 'telur');
      await settle(tester);

      expect(find.textContaining('Barang cocok'), findsOneWidget);
      expect(find.text('Terakhir beli'), findsOneWidget);
      expect(find.text('Termurah'), findsOneWidget,
          reason: 'Rp 26.000 lebih murah dari pembelian terakhir');
      expect(find.text('Bandingkan harga antar toko'), findsOneWidget);
      expect(repo.seen.last.query, 'telur');
    });

    testWidgets('filter tanggal lewat pilihan cepat', (tester) async {
      final FakeSearchRepository repo = FakeSearchRepository();
      await pumpApp(tester, repo: repo, home: const SearchScreen());

      await tester.tap(find.text('Tanggal'));
      await tester.pumpAndSettle();
      expect(find.text('Filter tanggal'), findsOneWidget);
      expect(find.text('30 hari terakhir'), findsOneWidget);
      expect(find.text('Pilih tanggal sendiri'), findsOneWidget);

      await tester.tap(find.text('30 hari terakhir'));
      await tester.pumpAndSettle();

      expect(find.text('Tanggal'), findsNothing,
          reason: 'berganti jadi rentang');
      expect(repo.seen.last.hasDateRange, isTrue);
      expect(repo.seen.last.from, isNotNull);
    });

    testWidgets('filter total struk dengan batas bawah', (tester) async {
      final FakeSearchRepository repo = FakeSearchRepository();
      await pumpApp(tester, repo: repo, home: const SearchScreen());

      await tester.ensureVisible(find.text('Total struk'));
      await tester.tap(find.text('Total struk'));
      await tester.pumpAndSettle();
      expect(find.text('Filter total struk'), findsOneWidget);

      // Kolom pertama pada lembar = total minimal.
      await tester.enterText(
          find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(TextField),
              )
              .first,
          '28000');
      await tester.pump();
      await tester.tap(find.text('Terapkan'));
      await tester.pumpAndSettle();

      expect(repo.seen.last.minTotal, 28000);
      expect(repo.seen.last.maxTotal, isNull);
      expect(find.textContaining('≥'), findsOneWidget);
    });

    testWidgets('filter kategori memilih beberapa kategori', (tester) async {
      final FakeSearchRepository repo = FakeSearchRepository();
      await pumpApp(tester, repo: repo, home: const SearchScreen());

      await tester.ensureVisible(find.text('Kategori'));
      await tester.pump();
      await tester.tap(find.text('Kategori'));
      await tester.pumpAndSettle();
      expect(find.text('Filter kategori'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Kesehatan'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'Bahan Makanan'));
      await tester.pump();
      await tester.ensureVisible(find.textContaining('Terapkan'));
      await tester.pump();
      await tester.tap(find.textContaining('Terapkan'));
      await tester.pumpAndSettle();

      expect(repo.seen.last.categoryIds, <int>{3, 7});
      expect(find.text('2 kategori'), findsOneWidget);
    });

    testWidgets('mengubah urutan lewat menu', (tester) async {
      final FakeSearchRepository repo = FakeSearchRepository();
      await pumpApp(tester, repo: repo, home: const SearchScreen());

      await tester.tap(find.byTooltip('Urutkan: Terbaru'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Total terbesar'));
      await tester.pumpAndSettle();

      expect(repo.seen.last.sort, SearchSort.highest);
      expect(find.byTooltip('Urutkan: Total terbesar'), findsOneWidget);
    });

    testWidgets('tidak ada hasil menampilkan keadaan kosong', (tester) async {
      final FakeSearchRepository repo = FakeSearchRepository();
      await pumpApp(tester, repo: repo, home: const SearchScreen());

      await tester.enterText(find.byType(TextField), 'zzzz');
      await settle(tester);

      expect(find.text('Tidak ada hasil'), findsOneWidget);
      expect(find.text('0 transaksi'), findsOneWidget);
    });
  });

  group('Layar Bandingkan Harga', () {
    testWidgets('daftar barang dengan toko termurah dan perubahan harga',
        (tester) async {
      final FakeSearchRepository repo = FakeSearchRepository();
      await pumpApp(tester, repo: repo, home: const PriceComparisonScreen());

      expect(find.text('Bandingkan Harga'), findsOneWidget);
      expect(find.textContaining('2 barang tercatat'), findsOneWidget);
      expect(find.text('Telur Ayam 1kg'), findsOneWidget,
          reason: 'empat penulisan nama digabung jadi satu barang');
      expect(find.text('Vitamin C'), findsOneWidget);
      expect(find.textContaining('4× dibeli · 2 toko'), findsOneWidget);
      expect(find.textContaining('Termurah di Alfamart'), findsOneWidget);
    });

    testWidgets(
        'mengetuk barang membuka rincian dengan grafik dan perbandingan',
        (tester) async {
      final FakeSearchRepository repo = FakeSearchRepository();
      await pumpApp(tester, repo: repo, home: const PriceComparisonScreen());

      await tester.tap(find.text('Telur Ayam 1kg'));
      await tester.pumpAndSettle();

      expect(find.text('Terendah'), findsOneWidget);
      expect(find.text('Rata-rata'), findsOneWidget);
      expect(find.text('Tertinggi'), findsOneWidget);
      expect(find.text('Perkembangan harga'), findsOneWidget);
      expect(find.text('Perbandingan antar toko'), findsOneWidget);
      expect(find.textContaining('Termurah di Alfamart'), findsWidgets);

      await tester.scrollUntilVisible(
        find.text('Riwayat pembelian'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Riwayat pembelian'), findsOneWidget);
    });

    testWidgets('pencarian menyaring barang dan "Bisa dibandingkan"',
        (tester) async {
      final FakeSearchRepository repo = FakeSearchRepository();
      await pumpApp(tester, repo: repo, home: const PriceComparisonScreen());

      await tester.enterText(find.byType(TextField), 'vit');
      await tester.pump();
      expect(find.text('Vitamin C'), findsOneWidget);
      expect(find.text('Telur Ayam 1kg'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      await tester.tap(find.text('Bisa dibandingkan'));
      await tester.pump();
      expect(find.text('Vitamin C'), findsNothing);
      expect(find.text('Telur Ayam 1kg'), findsOneWidget);
    });

    testWidgets(
        'dibuka dari hasil pencarian langsung menampilkan rincian barang',
        (tester) async {
      final FakeSearchRepository repo = FakeSearchRepository();
      await pumpApp(
        tester,
        repo: repo,
        home: const PriceComparisonScreen(initialQuery: 'telur'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Perkembangan harga'), findsOneWidget);
      expect(find.text('Perbandingan antar toko'), findsOneWidget);
    });
  });
}
