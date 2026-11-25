import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/core/utils/dashboard_period.dart';
import 'package:smart_receipt/data/models/income_model.dart';
import 'package:smart_receipt/data/models/savings_models.dart';
import 'package:smart_receipt/services/cash_flow_service.dart';
import 'package:smart_receipt/services/income_service.dart';
import 'package:smart_receipt/viewmodels/auth_viewmodel.dart';
import 'package:smart_receipt/viewmodels/cash_flow_viewmodel.dart';
import 'package:smart_receipt/viewmodels/income_viewmodel.dart';
import 'package:smart_receipt/viewmodels/savings_viewmodel.dart';

import 'helpers/fake_income_savings.dart';
import 'viewmodels_test.dart' show buildLoggedInAuth;

final DateTime today = DateTime(2026, 11, 25);

void main() {
  late AuthViewModel auth;
  late int userId;
  late FakeIncomeRepository incomes;
  late FakeSavingsRepository savings;
  late FakeExpenseRepository expenses;

  setUp(() async {
    auth = await buildLoggedInAuth();
    userId = auth.currentUser!.id!;
    incomes = FakeIncomeRepository();
    savings = FakeSavingsRepository();
    expenses = FakeExpenseRepository();
  });

  IncomeViewModel incomeVm() => IncomeViewModel(
        authViewModel: auth,
        incomeRepository: incomes,
        savingsRepository: savings,
        incomeService: IncomeService(incomes: incomes, savings: savings),
        clock: () => today,
      );

  SavingsViewModel savingsVm({bool withCashFlow = false}) => SavingsViewModel(
        authViewModel: auth,
        savingsRepository: savings,
        cashFlowService: withCashFlow
            ? CashFlowService(
                incomes: incomes, savings: savings, transactions: expenses)
            : null,
        clock: () => today,
      );

  Future<SavingsGoalModel> addGoal(
    String name,
    double target, {
    DateTime? deadline,
    double saved = 0,
  }) async {
    final SavingsGoalModel g = await savings.insertGoal(SavingsGoalModel(
      userId: userId,
      name: name,
      targetAmount: target,
      deadline: deadline,
      createdAt: DateTime(2026, 11, 1),
    ));
    if (saved != 0) {
      await savings.insertDeposit(SavingsDepositModel(
        goalId: g.id!,
        userId: userId,
        amount: saved,
        date: DateTime(2026, 11, 2),
        createdAt: today,
      ));
    }
    return g;
  }

  group('IncomeViewModel', () {
    test('menolak sumber kosong dan jumlah tidak valid', () async {
      final IncomeViewModel vm = incomeVm();

      expect(
        await vm.addIncome(source: '  ', amount: 1000, date: today),
        isNull,
      );
      expect(vm.errorMessage, 'Sumber pemasukan wajib diisi');

      expect(
        await vm.addIncome(source: 'Gaji', amount: 0, date: today),
        isNull,
      );
      expect(vm.errorMessage, 'Jumlah harus lebih dari 0');

      expect(
        await vm.addIncome(source: 'Gaji', amount: -5, date: today),
        isNull,
      );
      expect(incomes.incomes, isEmpty);
    });

    test('menyimpan pemasukan dan menghitung total bulan', () async {
      final IncomeViewModel vm = incomeVm();

      final IncomeModel? saved = await vm.addIncome(
        source: ' Uang saku ',
        amount: 3000000,
        date: DateTime(2026, 11, 1, 14, 30),
        notes: '  ',
      );
      await vm.addIncome(
          source: 'Freelance', amount: 500000, date: DateTime(2026, 11, 20));
      await vm.addIncome(
          source: 'Gaji', amount: 2800000, date: DateTime(2026, 10, 1));

      expect(saved!.source, 'Uang saku', reason: 'spasi dirapikan');
      expect(saved.date, DateTime(2026, 11, 1), reason: 'jam dibuang');
      expect(saved.notes, isNull, reason: 'catatan kosong tidak disimpan');
      expect(vm.incomes, hasLength(3));
      expect(vm.totalInMonth(DateTime(2026, 11)), 3500000);
      expect(vm.totalInMonth(DateTime(2026, 10)), 2800000);
    });

    test('mengubah dan menghapus pemasukan', () async {
      final IncomeViewModel vm = incomeVm();
      final IncomeModel saved =
          (await vm.addIncome(source: 'Gaji', amount: 1000000, date: today))!;

      expect(
        await vm.updateIncome(saved,
            source: 'Gaji pokok', amount: 1200000, date: today),
        isTrue,
      );
      expect(vm.incomes.single.amount, 1200000);
      expect(vm.incomes.single.source, 'Gaji pokok');

      expect(await vm.deleteIncome(vm.incomes.single), isTrue);
      expect(vm.incomes, isEmpty);
    });

    test('kegagalan penyimpanan dilaporkan, bukan dilempar', () async {
      final IncomeViewModel vm = incomeVm();
      incomes.failInsert = true;

      final IncomeModel? saved =
          await vm.addIncome(source: 'Gaji', amount: 1000, date: today);

      expect(saved, isNull);
      expect(vm.errorMessage, 'Gagal menyimpan pemasukan.');
    });

    test('saran alokasi mengikuti kebutuhan target berjalan saja', () async {
      await addGoal('Laptop', 8000000, deadline: DateTime(2027, 5, 1));
      await addGoal('Selesai', 100000,
          saved: 100000, deadline: DateTime(2027, 5, 1));
      await addGoal('Tanpa tenggat', 5000000);
      final IncomeViewModel vm = incomeVm();
      await vm.load();

      expect(vm.activeGoals.map((g) => g.goal.name),
          <String>['Laptop', 'Tanpa tenggat']);
      final Map<int, double> s = vm.suggestAllocation(3000000);
      expect(s, hasLength(1), reason: 'hanya Laptop yang punya jadwal');
      expect(s.values.single, closeTo(1400000, 100000));
    });

    test('alokasi menyimpan setoran yang tertaut ke pemasukan', () async {
      final SavingsGoalModel laptop =
          await addGoal('Laptop', 8000000, deadline: DateTime(2027, 5, 1));
      final SavingsGoalModel trip =
          await addGoal('Liburan', 1500000, deadline: DateTime(2027, 1, 31));
      final IncomeViewModel vm = incomeVm();
      final IncomeModel income = (await vm.addIncome(
          source: 'Uang saku', amount: 3000000, date: today))!;

      final bool ok = await vm.allocate(income, <int, double>{
        laptop.id!: 1000000,
        trip.id!: 500000,
        999: 0, // jumlah nol diabaikan
      });

      expect(ok, isTrue);
      expect(savings.deposits, hasLength(2));
      expect(savings.deposits.every((d) => d.incomeId == income.id), isTrue);
      expect(savings.deposits.every((d) => d.date == income.date), isTrue);
      expect((await savings.getGoal(laptop.id!))!.savedAmount, 1000000);
      expect((await savings.getGoal(trip.id!))!.savedAmount, 500000);
    });

    test('alokasi melebihi pemasukan ditolak dan tidak menyimpan apa pun',
        () async {
      final SavingsGoalModel laptop =
          await addGoal('Laptop', 8000000, deadline: DateTime(2027, 5, 1));
      final IncomeViewModel vm = incomeVm();
      final IncomeModel income = (await vm.addIncome(
          source: 'Freelance', amount: 500000, date: today))!;

      final bool ok =
          await vm.allocate(income, <int, double>{laptop.id!: 600000});

      expect(ok, isFalse);
      expect(vm.errorMessage, contains('melebihi'));
      expect(savings.deposits, isEmpty);
    });

    test('melewati alokasi (peta kosong) bukan galat', () async {
      final IncomeViewModel vm = incomeVm();
      final IncomeModel income =
          (await vm.addIncome(source: 'Gaji', amount: 1000000, date: today))!;

      expect(await vm.allocate(income, <int, double>{}), isTrue);
      expect(vm.errorMessage, isNull);
      expect(savings.deposits, isEmpty);
    });

    test('pemasukan berulang: dibuat sejak bulan mulai dan menyetor otomatis',
        () async {
      final SavingsGoalModel laptop =
          await addGoal('Laptop', 8000000, deadline: DateTime(2027, 5, 1));
      final IncomeViewModel vm = incomeVm();

      final RecurringCreated? result = await vm.addRecurring(
        source: 'Uang saku',
        amount: 3000000,
        startDate: DateTime(2026, 9, 1),
        autoGoalId: laptop.id,
        autoAmount: 500000,
      );

      expect(result!.created, hasLength(3), reason: 'Sep, Okt, Nov');
      expect(vm.incomes, hasLength(3));
      expect(vm.recurring.single.hasAutoAllocation, isTrue);
      expect(vm.goalNameOf(laptop.id!), 'Laptop');
      expect((await savings.getGoal(laptop.id!))!.savedAmount, 1500000);
    });

    test('pemasukan berulang menolak setoran otomatis yang tidak masuk akal',
        () async {
      final SavingsGoalModel laptop =
          await addGoal('Laptop', 8000000, deadline: DateTime(2027, 5, 1));
      final IncomeViewModel vm = incomeVm();

      expect(
        await vm.addRecurring(
          source: 'Uang saku',
          amount: 400000,
          startDate: today,
          autoGoalId: laptop.id,
          autoAmount: 500000,
        ),
        isNull,
      );
      expect(vm.errorMessage, contains('tidak boleh melebihi'));

      expect(
        await vm.addRecurring(
          source: 'Uang saku',
          amount: 400000,
          startDate: today,
          autoGoalId: laptop.id,
          autoAmount: 0,
        ),
        isNull,
      );
      expect(vm.recurring, isEmpty);
    });

    test('mematikan dan menghapus aturan berulang', () async {
      final IncomeViewModel vm = incomeVm();
      await vm.addRecurring(
          source: 'Uang saku',
          amount: 1000000,
          startDate: DateTime(2026, 11, 1));
      final RecurringIncomeModel rec = vm.recurring.single;

      await vm.setRecurringActive(rec, false);
      expect(vm.recurring.single.isActive, isFalse);

      await vm.deleteRecurring(vm.recurring.single);
      expect(vm.recurring, isEmpty);
      expect(vm.incomes, hasLength(1), reason: 'yang sudah tercatat tetap ada');
    });
  });

  group('SavingsViewModel', () {
    test('membuat target dan menolak masukan tidak valid', () async {
      final SavingsViewModel vm = savingsVm();

      expect(await vm.addGoal(name: '', targetAmount: 1000), isFalse);
      expect(vm.errorMessage, 'Nama target wajib diisi');
      expect(await vm.addGoal(name: 'Laptop', targetAmount: 0), isFalse);
      expect(
        await vm.addGoal(
          name: 'Laptop',
          targetAmount: 8000000,
          deadline: DateTime(2026, 11, 24),
        ),
        isFalse,
      );
      expect(vm.errorMessage, 'Tenggat tidak boleh sebelum hari ini');

      expect(
        await vm.addGoal(
          name: ' Laptop ',
          targetAmount: 8000000,
          deadline: DateTime(2027, 5, 1, 9),
        ),
        isTrue,
      );
      expect(vm.goals.single.goal.name, 'Laptop');
      expect(vm.goals.single.goal.deadline, DateTime(2027, 5, 1));
    });

    test('setor, tarik, dan batas penarikan', () async {
      final SavingsGoalModel g =
          await addGoal('Laptop', 8000000, deadline: DateTime(2027, 5, 1));
      final SavingsViewModel vm = savingsVm();
      await vm.load();

      expect(await vm.deposit(vm.goals.single.goal, amount: 1000000), isTrue);
      expect(vm.goals.single.goal.savedAmount, 1000000);
      expect(vm.totalSaved, 1000000);

      expect(await vm.deposit(vm.goals.single.goal, amount: 0), isFalse);

      expect(await vm.withdraw(vm.goals.single.goal, amount: 1500000), isFalse);
      expect(vm.errorMessage, contains('melebihi'));

      expect(await vm.withdraw(vm.goals.single.goal, amount: 400000), isTrue);
      expect(vm.goals.single.goal.savedAmount, 600000);

      final List<SavingsDepositModel> history =
          await vm.depositsOf(vm.goals.single.goal);
      expect(history.map((d) => d.amount),
          containsAll(<double>[1000000, -400000]));
      expect(g.id, isNotNull);
    });

    test('target tercapai pindah ke bawah dan tidak dihitung butuh per bulan',
        () async {
      await addGoal('Selesai', 100000,
          saved: 100000, deadline: DateTime(2027, 5, 1));
      await addGoal('Laptop', 8000000, deadline: DateTime(2027, 5, 1));
      final SavingsViewModel vm = savingsVm();
      await vm.load();

      expect(vm.goals.map((g) => g.goal.name), <String>['Laptop', 'Selesai']);
      expect(vm.activeGoals, hasLength(1));
      expect(vm.completedGoals.single.goal.name, 'Selesai');
      expect(vm.totalRequiredPerMonth, closeTo(8000000 / 6, 1));
    });

    test('mengubah target (tenggat dihapus) dan menghapus target', () async {
      final SavingsGoalModel g = await addGoal('Laptop', 8000000,
          deadline: DateTime(2027, 5, 1), saved: 500000);
      final SavingsViewModel vm = savingsVm();
      await vm.load();

      expect(
        await vm.updateGoal(vm.goals.single.goal,
            name: 'Laptop gaming', targetAmount: 10000000),
        isTrue,
      );
      expect(vm.goals.single.goal.name, 'Laptop gaming');
      expect(vm.goals.single.goal.deadline, isNull);
      expect(vm.goals.single.goal.savedAmount, 500000);

      expect(await vm.deleteGoal(vm.goals.single.goal), isTrue);
      expect(vm.goals, isEmpty);
      expect(savings.deposits, isEmpty);
      expect(g.id, isNotNull);
    });

    test('menghapus catatan setoran menghitung ulang saldo', () async {
      await addGoal('Laptop', 8000000,
          deadline: DateTime(2027, 5, 1), saved: 700000);
      final SavingsViewModel vm = savingsVm();
      await vm.load();
      final SavingsDepositModel d =
          (await vm.depositsOf(vm.goals.single.goal)).single;

      await vm.deleteDeposit(d);

      expect(vm.goals.single.goal.savedAmount, 0);
    });

    test('uji kenyataan: sisa uang cukup', () async {
      await addGoal('Laptop', 8000000, deadline: DateTime(2027, 5, 1));
      await incomes.insert(IncomeModel(
          userId: userId,
          source: 'Uang saku',
          amount: 3000000,
          date: DateTime(2026, 11, 1),
          createdAt: today));
      expenses.expenseByMonth['2026-11'] = 1000000;
      final SavingsViewModel vm = savingsVm(withCashFlow: true);
      await vm.load();

      expect(vm.monthlyCapacity, 2000000);
      expect(vm.realityCheck, RealityCheck.realistic);
    });

    test('uji kenyataan: tidak cukup, dengan kekurangan per bulan', () async {
      await addGoal('Laptop', 8000000, deadline: DateTime(2027, 5, 1));
      await incomes.insert(IncomeModel(
          userId: userId,
          source: 'Uang saku',
          amount: 3000000,
          date: DateTime(2026, 11, 1),
          createdAt: today));
      expenses.expenseByMonth['2026-11'] = 2400000;
      final SavingsViewModel vm = savingsVm(withCashFlow: true);
      await vm.load();

      expect(vm.monthlyCapacity, 600000);
      expect(vm.realityCheck, RealityCheck.shortfall);
      expect(vm.monthlyGap, closeTo(8000000 / 6 - 600000, 1));
    });

    test(
        'uji kenyataan: tanpa pemasukan atau tanpa target bertenggat = belum bisa dinilai',
        () async {
      await addGoal('Laptop', 8000000, deadline: DateTime(2027, 5, 1));
      SavingsViewModel vm = savingsVm(withCashFlow: true);
      await vm.load();
      expect(vm.realityCheck, RealityCheck.unknown,
          reason: 'belum ada pemasukan');

      incomes.incomes.add(IncomeModel(
          id: 1,
          userId: userId,
          source: 'Gaji',
          amount: 1000000,
          date: DateTime(2026, 11, 1),
          createdAt: today));
      savings.goals.clear();
      await addGoal('Tanpa tenggat', 5000000);
      vm = savingsVm(withCashFlow: true);
      await vm.load();
      expect(vm.realityCheck, RealityCheck.unknown,
          reason: 'tidak ada kebutuhan per bulan');
    });
  });

  group('CashFlowViewModel', () {
    CashFlowViewModel cashVm() => CashFlowViewModel(
          authViewModel: auth,
          service: CashFlowService(
              incomes: incomes, savings: savings, transactions: expenses),
          clock: () => today,
        );

    test('memuat arus kas periode dan tren enam bulan', () async {
      await incomes.insert(IncomeModel(
          userId: userId,
          source: 'Uang saku',
          amount: 3000000,
          date: DateTime(2026, 11, 1),
          createdAt: today));
      expenses.expenseByMonth['2026-11'] = 2000000;
      final SavingsGoalModel g =
          await addGoal('Laptop', 8000000, saved: 600000);
      expect(g.id, isNotNull);
      final CashFlowViewModel vm = cashVm();

      await vm.load(DashboardPeriod.month(2026, 11));

      expect(vm.flow.income, 3000000);
      expect(vm.flow.expense, 2000000);
      expect(vm.flow.saved, 600000);
      expect(vm.flow.free, 400000);
      expect(vm.trend, hasLength(6));
      expect(vm.trend.last.month, DateTime(2026, 11));
      expect(vm.hasAnyData, isTrue);
      expect(vm.hasFailed, isFalse);
    });

    test('periode tahun memakai seluruh tahun, tren berakhir di bulan ini',
        () async {
      await incomes.insert(IncomeModel(
          userId: userId,
          source: 'Gaji',
          amount: 1000000,
          date: DateTime(2026, 3, 1),
          createdAt: today));
      await incomes.insert(IncomeModel(
          userId: userId,
          source: 'Gaji',
          amount: 2000000,
          date: DateTime(2026, 11, 1),
          createdAt: today));
      final CashFlowViewModel vm = cashVm();

      await vm.load(DashboardPeriod.year(2026));

      expect(vm.flow.income, 3000000);
      expect(vm.trend.last.month, DateTime(2026, 11), reason: 'tahun berjalan');
      expect(vm.trendEnd(DashboardPeriod.year(2025)), DateTime(2025, 12));
    });

    test('periode hari memakai arus kas hari itu', () async {
      await incomes.insert(IncomeModel(
          userId: userId,
          source: 'Freelance',
          amount: 500000,
          date: DateTime(2026, 11, 10),
          createdAt: today));
      final CashFlowViewModel vm = cashVm();

      await vm.load(DashboardPeriod.day(DateTime(2026, 11, 10)));
      expect(vm.flow.income, 500000);

      await vm.load(DashboardPeriod.day(DateTime(2026, 11, 11)));
      expect(vm.flow.income, 0);
    });

    test('tanpa data sama sekali: kosong', () async {
      final CashFlowViewModel vm = cashVm();
      await vm.load(DashboardPeriod.month(2026, 11));

      expect(vm.hasAnyData, isFalse);
      expect(vm.flow.free, 0);
    });
  });
}
