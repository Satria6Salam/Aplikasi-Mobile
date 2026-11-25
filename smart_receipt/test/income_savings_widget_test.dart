import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:smart_receipt/core/theme/app_theme.dart';
import 'package:smart_receipt/core/utils/dashboard_period.dart';
import 'package:smart_receipt/core/utils/formatters.dart';
import 'package:smart_receipt/data/models/income_model.dart';
import 'package:smart_receipt/data/models/savings_models.dart';
import 'package:smart_receipt/data/repositories/income_repository.dart';
import 'package:smart_receipt/data/repositories/savings_repository.dart';
import 'package:smart_receipt/services/cash_flow_service.dart';
import 'package:smart_receipt/services/income_service.dart';
import 'package:smart_receipt/viewmodels/auth_viewmodel.dart';
import 'package:smart_receipt/viewmodels/dashboard_viewmodel.dart';
import 'package:smart_receipt/views/income/income_screen.dart';
import 'package:smart_receipt/views/savings/savings_screen.dart';
import 'package:smart_receipt/views/widgets/cash_flow_card.dart';
import 'package:smart_receipt/views/widgets/custom_button.dart';

import 'helpers/fake_income_savings.dart';
import 'viewmodels_test.dart' show buildLoggedInAuth;

/// Rupiah seperti yang ditampilkan aplikasi (karakter spasinya khusus).
String rp(num value) => AppFormatters.rupiah(value.toDouble());

/// DashboardViewModel tiruan: hanya data yang dibaca kartu Arus Kas.
class FakeDashboard extends ChangeNotifier
    with Fake
    implements DashboardViewModel {
  FakeDashboard(this._period);

  final DashboardPeriod _period;

  @override
  DashboardPeriod get period => _period;
  @override
  double get total => 2000000;
  @override
  int get transactionCount => 5;
  @override
  bool get isLoading => false;
}

class Harness {
  Harness(this.auth, this.incomes, this.savings, this.expenses);

  final AuthViewModel auth;
  final FakeIncomeRepository incomes;
  final FakeSavingsRepository savings;
  final FakeExpenseRepository expenses;

  int get userId => auth.currentUser!.id!;
}

Future<Harness> pumpApp(
  WidgetTester tester, {
  required Widget home,
  Widget Function(Harness)? wrap,
}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 2.0; // 450 x 900 dp.
  addTearDown(tester.view.reset);

  final AuthViewModel auth =
      await tester.runAsync(buildLoggedInAuth) as AuthViewModel;
  final Harness h = Harness(
    auth,
    FakeIncomeRepository(),
    FakeSavingsRepository(),
    FakeExpenseRepository(),
  );

  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (BuildContext _, GoRouterState __) => home),
      GoRoute(
        path: '/incomes',
        builder: (BuildContext _, GoRouterState __) => const IncomeScreen(),
      ),
    ],
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: <Provider<dynamic>>[
        Provider<IncomeRepository>.value(value: h.incomes),
        Provider<SavingsRepository>.value(value: h.savings),
        Provider<IncomeService>.value(
          value: IncomeService(incomes: h.incomes, savings: h.savings),
        ),
        Provider<CashFlowService>.value(
          value: CashFlowService(
            incomes: h.incomes,
            savings: h.savings,
            transactions: h.expenses,
          ),
        ),
      ],
      child: ChangeNotifierProvider<AuthViewModel>.value(
        value: auth,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  return h;
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder inSheet(Finder matching) =>
    find.descendant(of: find.byType(BottomSheet), matching: matching);

/// Target Laptop Rp 8 jt dengan tenggat sekitar 6 bulan dari sekarang.
Future<SavingsGoalModel> seedGoal(Harness h,
    {String name = 'Laptop', double target = 8000000}) {
  final DateTime now = DateTime.now();
  return h.savings.insertGoal(SavingsGoalModel(
    userId: h.userId,
    name: name,
    targetAmount: target,
    deadline: DateTime(now.year, now.month + 6, now.day),
    createdAt: now,
  ));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  group('Layar Pemasukan', () {
    testWidgets('kosong: mengajak mencatat pemasukan', (tester) async {
      await pumpApp(tester, home: const IncomeScreen());

      expect(find.text('Belum ada pemasukan'), findsOneWidget);
      expect(find.text('Catat Pemasukan'), findsWidgets);
    });

    testWidgets('mencatat pemasukan tanpa target: langsung tersimpan',
        (tester) async {
      final Harness h = await pumpApp(tester, home: const IncomeScreen());

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Catat pemasukan'), findsOneWidget);

      await tester.enterText(inSheet(find.byType(TextField)).first, '3000000');
      await tapVisible(tester, find.widgetWithText(ActionChip, 'Uang saku'));
      await tapVisible(tester, find.text('Simpan'));

      expect(h.incomes.incomes, hasLength(1));
      expect(h.incomes.incomes.single.amount, 3000000);
      expect(h.incomes.incomes.single.source, 'Uang saku');
      expect(find.text('Sisihkan untuk target?'), findsNothing,
          reason: 'belum ada target tabungan');
      expect(find.text('+${rp(3000000)}'), findsOneWidget);
    });

    testWidgets('jumlah dan sumber wajib diisi', (tester) async {
      final Harness h = await pumpApp(tester, home: const IncomeScreen());

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Simpan'));

      expect(find.text('Jumlah harus lebih dari 0'), findsOneWidget);
      expect(find.text('Sumber wajib diisi'), findsOneWidget);
      expect(h.incomes.incomes, isEmpty);
    });

    testWidgets('Pilihan C: setelah mencatat, aplikasi menawarkan penyisihan',
        (tester) async {
      final Harness h = await pumpApp(tester, home: const IncomeScreen());
      final SavingsGoalModel laptop = await seedGoal(h);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(inSheet(find.byType(TextField)).first, '3000000');
      await tapVisible(tester, find.widgetWithText(ActionChip, 'Uang saku'));
      await tapVisible(tester, find.text('Simpan'));

      // Lembar penawaran muncul, jumlah awal diisi dari kebutuhan per bulan.
      expect(find.text('Sisihkan untuk target?'), findsOneWidget);
      expect(find.text('Laptop'), findsWidgets);
      final String suggested = tester
          .widgetList<TextField>(inSheet(find.byType(TextField)))
          .first
          .controller!
          .text;
      expect(suggested, isNotEmpty);
      expect(find.text('Sisa untuk Anda'), findsOneWidget);

      await tapVisible(tester, find.text('Sisihkan'));

      expect(h.savings.deposits, hasLength(1));
      final SavingsDepositModel d = h.savings.deposits.single;
      expect(d.goalId, laptop.id);
      expect(d.incomeId, h.incomes.incomes.single.id,
          reason: 'setoran tertaut ke pemasukan asalnya');
      expect(
        suggested.replaceAll('.', ''),
        d.amount.round().toString(),
        reason: 'jumlah yang disetor = jumlah pada kotak',
      );
      expect(find.textContaining('disisihkan ke tabungan'), findsOneWidget);
    });

    testWidgets('Pilihan C: jumlah bisa diubah sebelum disisihkan',
        (tester) async {
      final Harness h = await pumpApp(tester, home: const IncomeScreen());
      await seedGoal(h);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(inSheet(find.byType(TextField)).first, '3000000');
      await tapVisible(tester, find.widgetWithText(ActionChip, 'Gaji'));
      await tapVisible(tester, find.text('Simpan'));

      await tester.enterText(inSheet(find.byType(TextField)).first, '750000');
      await tester.pump();
      await tapVisible(tester, find.text('Sisihkan'));

      expect(h.savings.deposits.single.amount, 750000);
    });

    testWidgets('Pilihan C: "Lewati" tidak menyimpan setoran apa pun',
        (tester) async {
      final Harness h = await pumpApp(tester, home: const IncomeScreen());
      await seedGoal(h);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(inSheet(find.byType(TextField)).first, '3000000');
      await tapVisible(tester, find.widgetWithText(ActionChip, 'Uang saku'));
      await tapVisible(tester, find.text('Simpan'));
      expect(find.text('Sisihkan untuk target?'), findsOneWidget);

      await tapVisible(tester, find.text('Lewati'));

      expect(h.savings.deposits, isEmpty);
      expect(h.incomes.incomes, hasLength(1),
          reason: 'pemasukan tetap tersimpan');
      expect(find.text('Sisihkan untuk target?'), findsNothing);
    });

    testWidgets('Pilihan C: tidak boleh menyisihkan lebih dari pemasukan',
        (tester) async {
      final Harness h = await pumpApp(tester, home: const IncomeScreen());
      await seedGoal(h);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(inSheet(find.byType(TextField)).first, '400000');
      await tapVisible(tester, find.widgetWithText(ActionChip, 'Freelance'));
      await tapVisible(tester, find.text('Simpan'));

      await tester.enterText(inSheet(find.byType(TextField)).first, '500000');
      await tester.pump();

      expect(find.text('Melebihi pemasukan'), findsOneWidget);
      final CustomButton save = tester
          .widget<CustomButton>(find.widgetWithText(CustomButton, 'Sisihkan'));
      expect(save.onPressed, isNull, reason: 'tombol Sisihkan nonaktif');
      expect(h.savings.deposits, isEmpty);
    });

    testWidgets('pemasukan berulang dengan setoran otomatis ke target',
        (tester) async {
      final Harness h = await pumpApp(tester, home: const IncomeScreen());
      final SavingsGoalModel laptop = await seedGoal(h);
      await tester.pumpWidget(const SizedBox());
      await pumpAppAgain(tester, h); // layar baru memuat target yang ada

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(inSheet(find.byType(TextField)).first, '3000000');
      await tapVisible(tester, find.widgetWithText(ActionChip, 'Uang saku'));
      await tapVisible(tester, find.text('Berulang tiap bulan'));
      await tapVisible(tester, find.text('Otomatis sisihkan ke target'));
      await tester.enterText(inSheet(find.byType(TextField)).last, '500000');
      await tester.pump();
      await tapVisible(tester, find.text('Simpan'));

      expect(h.incomes.recurring, hasLength(1));
      expect(h.incomes.recurring.single.autoGoalId, laptop.id);
      expect(h.incomes.recurring.single.autoAmount, 500000);
      expect(h.incomes.incomes, isNotEmpty,
          reason: 'bulan ini langsung dibuat');
      expect(h.savings.deposits.first.amount, 500000);
      expect(find.text('Pemasukan berulang'), findsOneWidget);
      expect(find.text('Otomatis'), findsWidgets);
    });

    testWidgets('mengubah dan menghapus pemasukan', (tester) async {
      final Harness h = await pumpApp(tester, home: const IncomeScreen());
      await h.incomes.insert(IncomeModel(
        userId: h.userId,
        source: 'Gaji',
        amount: 1000000,
        date: DateTime.now(),
        createdAt: DateTime.now(),
      ));
      await tester.pumpWidget(const SizedBox());
      await pumpAppAgain(tester, h);

      await tester.tap(find.text('Gaji'));
      await tester.pumpAndSettle();
      expect(find.text('Ubah pemasukan'), findsOneWidget);

      await tester.enterText(inSheet(find.byType(TextField)).first, '1500000');
      await tapVisible(tester, find.text('Simpan perubahan'));
      expect(h.incomes.incomes.single.amount, 1500000);

      await tester.tap(find.text('Gaji'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Hapus pemasukan'));
      await tester.tap(find.text('Hapus').last);
      await tester.pumpAndSettle();

      expect(h.incomes.incomes, isEmpty);
    });
  });

  group('Layar Target Tabungan', () {
    testWidgets('kosong: mengajak membuat target', (tester) async {
      await pumpApp(tester, home: const SavingsScreen());

      expect(find.text('Belum ada target tabungan'), findsOneWidget);
    });

    testWidgets('membuat target: pratinjau kebutuhan per bulan',
        (tester) async {
      final Harness h = await pumpApp(tester, home: const SavingsScreen());

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Target tabungan baru'), findsOneWidget);

      await tester.enterText(
          inSheet(find.byType(TextField)).at(0), 'Laptop baru');
      await tester.enterText(inSheet(find.byType(TextField)).at(1), '8000000');
      await tester.pump();
      await tapVisible(tester, find.widgetWithText(ActionChip, '6 bulan'));

      expect(find.textContaining('Perlu menabung'), findsOneWidget);
      expect(find.textContaining('selama 6 bulan'), findsOneWidget);

      await tapVisible(tester, find.text('Buat target'));

      expect(h.savings.goals.single.name, 'Laptop baru');
      expect(h.savings.goals.single.targetAmount, 8000000);
      expect(h.savings.goals.single.deadline, isNotNull);
      expect(find.text('Laptop baru'), findsOneWidget);
      expect(
          find.textContaining('${rp(0)} dari ${rp(8000000)}'), findsOneWidget);
      expect(find.textContaining('per bulan'), findsWidgets);
    });

    testWidgets('validasi: nama dan jumlah wajib', (tester) async {
      final Harness h = await pumpApp(tester, home: const SavingsScreen());

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Buat target'));

      expect(find.text('Nama target wajib diisi'), findsOneWidget);
      expect(find.text('Target harus lebih dari 0'), findsOneWidget);
      expect(h.savings.goals, isEmpty);
    });

    testWidgets('setor ke target memperbarui progres', (tester) async {
      final Harness h = await pumpApp(tester, home: const SavingsScreen());
      await seedGoal(h);
      await tester.pumpWidget(const SizedBox());
      await pumpAppAgain(tester, h, home: const SavingsScreen());

      expect(find.text('Laptop'), findsOneWidget);
      await tester.tap(find.widgetWithText(CustomButton, 'Setor'));
      await tester.pumpAndSettle();
      expect(find.text('Setor ke "Laptop"'), findsOneWidget);

      await tester.enterText(inSheet(find.byType(TextField)).first, '1000000');
      await tester.pump();
      await tapVisible(
          tester, inSheet(find.widgetWithText(CustomButton, 'Setor')));

      expect(h.savings.deposits.single.amount, 1000000);
      expect(find.textContaining('${rp(1000000)} dari ${rp(8000000)}'),
          findsOneWidget);
      expect(find.text('Tarik'), findsOneWidget,
          reason: 'tombol tarik muncul setelah ada tabungan');
    });

    testWidgets('penarikan tidak boleh melebihi tabungan', (tester) async {
      final Harness h = await pumpApp(tester, home: const SavingsScreen());
      final SavingsGoalModel g = await seedGoal(h);
      await h.savings.insertDeposit(SavingsDepositModel(
        goalId: g.id!,
        userId: h.userId,
        amount: 300000,
        date: DateTime.now(),
        createdAt: DateTime.now(),
      ));
      await tester.pumpWidget(const SizedBox());
      await pumpAppAgain(tester, h, home: const SavingsScreen());

      await tester.tap(find.widgetWithText(CustomButton, 'Tarik'));
      await tester.pumpAndSettle();
      await tester.enterText(inSheet(find.byType(TextField)).first, '500000');
      await tester.pump();
      await tapVisible(
          tester, inSheet(find.widgetWithText(CustomButton, 'Tarik')));

      expect(find.textContaining('Melebihi tabungan'), findsOneWidget);
      expect(h.savings.deposits, hasLength(1));
    });

    testWidgets('uji kenyataan: sisa uang tidak cukup untuk target',
        (tester) async {
      final Harness h = await pumpApp(tester, home: const SavingsScreen());
      await seedGoal(h);
      final DateTime now = DateTime.now();
      await h.incomes.insert(IncomeModel(
        userId: h.userId,
        source: 'Uang saku',
        amount: 3000000,
        date: DateTime(now.year, now.month, 1),
        createdAt: now,
      ));
      h.expenses.expenseByMonth[
          '${now.year}-${now.month.toString().padLeft(2, '0')}'] = 2400000;
      await tester.pumpWidget(const SizedBox());
      await pumpAppAgain(tester, h, home: const SavingsScreen());

      expect(find.textContaining('Kurang sekitar'), findsOneWidget);
      expect(find.textContaining('Kurangi belanja atau perpanjang tenggat'),
          findsOneWidget);
    });

    testWidgets('uji kenyataan: tanpa pemasukan mengajak mencatat',
        (tester) async {
      final Harness h = await pumpApp(tester, home: const SavingsScreen());
      await seedGoal(h);
      await tester.pumpWidget(const SizedBox());
      await pumpAppAgain(tester, h, home: const SavingsScreen());

      expect(find.textContaining('Catat pemasukan bulan ini'), findsOneWidget);
    });

    testWidgets('rincian target: riwayat dan hapus target', (tester) async {
      final Harness h = await pumpApp(tester, home: const SavingsScreen());
      final SavingsGoalModel g = await seedGoal(h);
      await h.savings.insertDeposit(SavingsDepositModel(
        goalId: g.id!,
        userId: h.userId,
        amount: 400000,
        date: DateTime.now(),
        notes: 'Disisihkan dari Uang saku',
        createdAt: DateTime.now(),
      ));
      await tester.pumpWidget(const SizedBox());
      await pumpAppAgain(tester, h, home: const SavingsScreen());

      await tester.tap(find.text('Laptop'));
      await tester.pumpAndSettle();
      expect(find.text('Riwayat'), findsOneWidget);
      expect(find.text('+${rp(400000)}'), findsOneWidget);
      expect(find.text('Disisihkan dari Uang saku'), findsOneWidget);

      await tapVisible(tester, find.text('Hapus target'));
      await tester.tap(find.text('Hapus').last);
      await tester.pumpAndSettle();

      expect(h.savings.goals, isEmpty);
      expect(h.savings.deposits, isEmpty);
    });
  });

  group('Kartu Pemasukan & Sisa Uang di Dasbor', () {
    Future<Harness> pumpCard(
      WidgetTester tester, {
      void Function(Harness)? seed,
    }) async {
      final Harness h = await pumpApp(tester, home: const SizedBox());
      seed?.call(h);
      await tester.pumpWidget(const SizedBox());
      await pumpAppAgain(
        tester,
        h,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChangeNotifierProvider<DashboardViewModel>.value(
              value: FakeDashboard(DashboardPeriod.month(2026, 10)),
              child: const CashFlowScope(
                child: Column(
                  children: [CashFlowBalanceCard(), CashFlowTrendCard()],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      return h;
    }

    testWidgets('menampilkan pemasukan, pengeluaran, tabungan, dan sisa',
        (tester) async {
      await pumpCard(tester, seed: (Harness h) {
        h.incomes.incomes.add(IncomeModel(
          id: 1,
          userId: h.userId,
          source: 'Uang saku',
          amount: 3000000,
          date: DateTime(2026, 10, 1),
          createdAt: DateTime(2026, 10, 1),
        ));
        h.expenses.expenseByMonth['2026-10'] = 2000000;
        h.savings.goals.add(SavingsGoalModel(
          id: 1,
          userId: h.userId,
          name: 'Laptop',
          targetAmount: 8000000,
          createdAt: DateTime(2026, 10, 1),
        ));
        h.savings.deposits.add(SavingsDepositModel(
          id: 1,
          goalId: 1,
          userId: h.userId,
          amount: 600000,
          date: DateTime(2026, 10, 1),
          createdAt: DateTime(2026, 10, 1),
        ));
      });

      expect(find.text('Pemasukan & Sisa Uang'), findsOneWidget);
      expect(find.text('Sisa uang bebas'), findsOneWidget);
      expect(find.text(rp(400000)), findsOneWidget,
          reason: '3 jt − 2 jt − 0,6 jt');
      expect(find.text(rp(3000000)), findsOneWidget);
      expect(find.text(rp(2000000)), findsOneWidget);
      expect(find.text(rp(600000)), findsOneWidget);
      expect(find.text('Defisit'), findsNothing);
      expect(find.textContaining('Dibelanjakan 67% dari pemasukan'),
          findsOneWidget);
      expect(find.text('6 bulan terakhir'), findsOneWidget);
      expect(find.text('Pemasukan vs Pengeluaran'), findsOneWidget);
    });

    testWidgets('defisit ditandai merah', (tester) async {
      await pumpCard(tester, seed: (Harness h) {
        h.incomes.incomes.add(IncomeModel(
          id: 1,
          userId: h.userId,
          source: 'Uang saku',
          amount: 1000000,
          date: DateTime(2026, 10, 1),
          createdAt: DateTime(2026, 10, 1),
        ));
        h.expenses.expenseByMonth['2026-10'] = 1500000;
      });

      expect(find.text('Defisit'), findsOneWidget);
      expect(find.text(rp(-500000)), findsOneWidget);
    });

    testWidgets('tanpa pemasukan: mengajak mencatat', (tester) async {
      await pumpCard(tester);

      expect(find.textContaining('Belum ada pemasukan pada periode ini'),
          findsOneWidget);
      expect(find.text('6 bulan terakhir'), findsNothing);
      expect(find.text('Pemasukan'), findsWidgets);
      expect(find.text('Tabungan'), findsOneWidget);
    });
  });
}

/// Membangun ulang aplikasi memakai data yang sama (untuk data yang diisi
/// setelah layar pertama dibuat).
Future<void> pumpAppAgain(
  WidgetTester tester,
  Harness h, {
  Widget home = const IncomeScreen(),
}) async {
  final GoRouter router = GoRouter(
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (BuildContext _, GoRouterState __) => home),
      GoRoute(
        path: '/incomes',
        builder: (BuildContext _, GoRouterState __) => const IncomeScreen(),
      ),
    ],
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: <Provider<dynamic>>[
        Provider<IncomeRepository>.value(value: h.incomes),
        Provider<SavingsRepository>.value(value: h.savings),
        Provider<IncomeService>.value(
          value: IncomeService(incomes: h.incomes, savings: h.savings),
        ),
        Provider<CashFlowService>.value(
          value: CashFlowService(
            incomes: h.incomes,
            savings: h.savings,
            transactions: h.expenses,
          ),
        ),
      ],
      child: ChangeNotifierProvider<AuthViewModel>.value(
        value: h.auth,
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}
