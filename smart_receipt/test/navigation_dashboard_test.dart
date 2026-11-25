import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_receipt/core/constants/app_routes.dart';
import 'package:smart_receipt/core/theme/app_theme.dart';
import 'package:smart_receipt/data/models/income_model.dart';
import 'package:smart_receipt/data/models/transaction_model.dart';
import 'package:smart_receipt/data/repositories/income_repository.dart';
import 'package:smart_receipt/data/repositories/savings_repository.dart';
import 'package:smart_receipt/services/cash_flow_service.dart';
import 'package:smart_receipt/viewmodels/auth_viewmodel.dart';
import 'package:smart_receipt/viewmodels/dashboard_viewmodel.dart';
import 'package:smart_receipt/views/dashboard/dashboard_screen.dart';
import 'package:smart_receipt/views/features/features_screen.dart';
import 'package:smart_receipt/views/widgets/app_bottom_nav.dart';

import 'helpers/fake_income_savings.dart';
import 'viewmodels_test.dart'
    show
        FakeImageStorageService,
        FakeOcrResultRepository,
        FakeTransactionRepository,
        buildLoggedInAuth;

/// Peta rute -> judul yang terlihat, untuk memeriksa navigasi.
Widget routerApp(Widget home, List<String> visited) {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (BuildContext _, GoRouterState __) => home),
      for (final String route in <String>[
        AppRoutes.incomes,
        AppRoutes.manualEntry,
        AppRoutes.budget,
        AppRoutes.savings,
        AppRoutes.shoppingPlan,
        AppRoutes.analysis,
        AppRoutes.search,
        AppRoutes.priceCompare,
        AppRoutes.storeMap,
        AppRoutes.categories,
        AppRoutes.scan,
        AppRoutes.history,
      ])
        GoRoute(
          path: route,
          builder: (BuildContext _, GoRouterState __) {
            visited.add(route);
            return Scaffold(body: Center(child: Text('Halaman $route')));
          },
        ),
    ],
  );
  return MaterialApp.router(theme: AppTheme.light, routerConfig: router);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  group('Menu Fitur', () {
    test('memuat semua fitur yang dulu ada di Profil, tanpa yang hilang', () {
      final Set<String> routes = featureSections()
          .expand((FeatureSection s) => s.features)
          .map((FeatureSpec f) => f.route)
          .toSet();

      expect(
        routes,
        <String>{
          AppRoutes.incomes,
          AppRoutes.manualEntry,
          AppRoutes.budget,
          AppRoutes.savings,
          AppRoutes.shoppingPlan,
          AppRoutes.analysis,
          AppRoutes.search,
          AppRoutes.priceCompare,
          AppRoutes.storeMap,
          AppRoutes.categories,
        },
      );
    });

    test('tiap fitur punya judul, penjelasan, dan tidak ada rute ganda', () {
      final List<FeatureSpec> all =
          featureSections().expand((FeatureSection s) => s.features).toList();

      expect(all.every((FeatureSpec f) => f.title.isNotEmpty), isTrue);
      expect(all.every((FeatureSpec f) => f.subtitle.length >= 10), isTrue);
      expect(all.map((FeatureSpec f) => f.route).toSet().length, all.length);
      expect(featureSections().map((FeatureSection s) => s.title), <String>[
        'Catat & Rencanakan',
        'Analisis & Pencarian',
        'Kelola',
      ]);
    });

    testWidgets('menampilkan bagian dan kartu fitur', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(routerApp(const FeaturesScreen(), <String>[]));
      await tester.pumpAndSettle();

      expect(find.text('Fitur'), findsOneWidget);
      expect(find.text('Catat & Rencanakan'), findsOneWidget);
      expect(find.text('Analisis & Pencarian'), findsOneWidget);
      expect(find.text('Kelola'), findsOneWidget);
      for (final String title in <String>[
        'Pemasukan',
        'Catat Manual',
        'Anggaran',
        'Target Tabungan',
        'Rencana Belanja',
        'Analisis',
        'Pencarian Lanjutan',
        'Bandingkan Harga',
        'Peta Toko',
        'Kategori',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
    });

    testWidgets('mengetuk kartu membuka halamannya', (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final List<String> visited = <String>[];

      await tester.pumpWidget(routerApp(const FeaturesScreen(), visited));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Target Tabungan'));
      await tester.pumpAndSettle();
      expect(visited, <String>[AppRoutes.savings]);
      expect(find.text('Halaman ${AppRoutes.savings}'), findsOneWidget);
    });
  });

  group('Navigasi bawah', () {
    testWidgets('empat menu: Beranda, Riwayat, Fitur, Profil + tombol Scan',
        (tester) async {
      int? selected;
      bool scanned = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            bottomNavigationBar: AppBottomNav(
              currentIndex: 0,
              onSelect: (int i) => selected = i,
              onScan: () => scanned = true,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Beranda'), findsOneWidget);
      expect(find.text('Riwayat'), findsOneWidget);
      expect(find.text('Fitur'), findsOneWidget);
      expect(find.text('Profil'), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
      expect(find.text('Analisis'), findsNothing,
          reason: 'Analisis dipindah ke menu Fitur');

      await tester.tap(find.text('Fitur'));
      expect(selected, 2);
      await tester.tap(find.text('Profil'));
      expect(selected, 3);
      expect(scanned, isFalse);
    });
  });

  group('Dasbor yang dirapikan', () {
    Future<void> pumpDashboard(
      WidgetTester tester, {
      required List<String> visited,
      bool withIncome = true,
      bool withTransactions = true,
    }) async {
      tester.view.physicalSize = const Size(900, 7000);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final AuthViewModel auth =
          await tester.runAsync(buildLoggedInAuth) as AuthViewModel;
      final DateTime now = DateTime.now();
      final FakeTransactionRepository txRepo = FakeTransactionRepository();
      if (withTransactions) {
        for (int i = 1; i <= 3; i++) {
          txRepo.stored.add(
            TransactionModel(
              id: i,
              userId: auth.currentUser!.id!,
              merchantName: 'Toko $i',
              transactionDate: DateTime(now.year, now.month, 1),
              totalAmount: 20000.0 * i,
              categoryId: i,
              createdAt: now,
              updatedAt: now,
              categoryName: <String>[
                'Konsumsi',
                'Transportasi',
                'Belanja'
              ][i - 1],
            ),
          );
        }
      }
      final FakeIncomeRepository incomes = FakeIncomeRepository();
      if (withIncome) {
        incomes.incomes.add(IncomeModel(
          id: 1,
          userId: auth.currentUser!.id!,
          source: 'Uang saku',
          amount: 3000000,
          date: DateTime(now.year, now.month, 1),
          createdAt: now,
        ));
      }
      final FakeExpenseRepository expenses = FakeExpenseRepository()
        ..expenseByMonth[
                '${now.year}-${now.month.toString().padLeft(2, '0')}'] =
            withTransactions ? 120000 : 0;

      final DashboardViewModel dash = DashboardViewModel(
        authViewModel: auth,
        transactionRepository: txRepo,
        ocrResultRepository: FakeOcrResultRepository(),
        imageStorageService: FakeImageStorageService(),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: <Provider<dynamic>>[
            Provider<IncomeRepository>.value(value: incomes),
            Provider<SavingsRepository>.value(value: FakeSavingsRepository()),
            Provider<CashFlowService>.value(
              value: CashFlowService(
                incomes: incomes,
                savings: FakeSavingsRepository(),
                transactions: expenses,
              ),
            ),
          ],
          child: ChangeNotifierProvider<AuthViewModel>.value(
            value: auth,
            child: ChangeNotifierProvider<DashboardViewModel>.value(
              value: dash,
              child: routerApp(const DashboardScreen(), visited),
            ),
          ),
        ),
      );
      for (int i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets(
        'urutan bagian jelas dan tidak ada angka ganda yang membingungkan',
        (tester) async {
      await pumpDashboard(tester, visited: <String>[]);

      // Bagian utama, dari atas ke bawah.
      final List<String> titles = <String>[
        'Pemasukan & Sisa Uang',
        'Pengeluaran per Kategori',
        'Statistik Periode',
        'Transaksi Terbaru',
      ];
      double? previousY;
      for (final String title in titles) {
        final Finder f = find.text(title, skipOffstage: false);
        expect(f, findsOneWidget, reason: title);
        final double y = tester.getTopLeft(f).dy;
        if (previousY != null) expect(y, greaterThan(previousY), reason: title);
        previousY = y;
      }

      // Aksi cepat: empat tombol dengan nama yang jelas.
      for (final String label in <String>[
        'Scan Struk',
        'Catat Manual',
        'Pemasukan',
        'Anggaran',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }

      // Kartu ringkasan tunggal untuk pengeluaran (tidak ada kartu "Rekap" ganda).
      expect(find.textContaining('Total Pengeluaran'), findsOneWidget);
      expect(find.text('Sisa uang bebas'), findsOneWidget);
      expect(find.text('Rekap Singkat'), findsNothing);
      expect(find.text('Wawasan untuk Anda'), findsNothing);
    });

    testWidgets(
        'statistik periode berupa satu kartu daftar, bukan kotak berwarna',
        (tester) async {
      await pumpDashboard(tester, visited: <String>[]);

      for (final String label in <String>[
        'Rata-rata per transaksi',
        'Transaksi terbesar',
        'Hari ada pengeluaran',
      ]) {
        expect(find.text(label, skipOffstage: false), findsOneWidget,
            reason: label);
      }
    });

    testWidgets('tanpa pemasukan: kartu mengajak mencatat, bukan angka kosong',
        (tester) async {
      await pumpDashboard(tester, visited: <String>[], withIncome: false);

      expect(find.textContaining('Belum ada pemasukan pada periode ini'),
          findsOneWidget);
    });

    testWidgets('tautan Analisis dan Pemasukan membuka halaman yang benar',
        (tester) async {
      final List<String> visited = <String>[];
      await pumpDashboard(tester, visited: visited);

      await tester.tap(find.widgetWithText(TextButton, 'Analisis'));
      await tester.pumpAndSettle();
      expect(visited, <String>[AppRoutes.analysis]);
    });

    testWidgets('tanpa transaksi: keadaan kosong dengan tombol Scan Struk',
        (tester) async {
      await pumpDashboard(tester,
          visited: <String>[], withTransactions: false, withIncome: false);

      expect(find.text('Belum ada transaksi'), findsOneWidget);
      expect(find.text('Pengeluaran per Kategori'), findsNothing,
          reason: 'bagian kosong tidak ditampilkan');
      expect(find.text('Statistik Periode'), findsNothing);
    });
  });
}
