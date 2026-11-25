import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/data/database/database_schema.dart';
import 'package:smart_receipt/data/models/income_model.dart';
import 'package:smart_receipt/data/models/savings_models.dart';
import 'package:smart_receipt/data/repositories/income_repository.dart';
import 'package:smart_receipt/data/repositories/savings_repository.dart';
import 'package:smart_receipt/data/repositories/transaction_repository.dart';
import 'package:smart_receipt/services/cash_flow_service.dart';
import 'package:smart_receipt/services/income_service.dart';
import 'package:smart_receipt/services/savings_planner.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/memory_database.dart';

SavingsGoalModel goal({
  int id = 1,
  String name = 'Laptop',
  double target = 8000000,
  double saved = 0,
  DateTime? created,
  DateTime? deadline,
  bool noDeadline = false,
}) =>
    SavingsGoalModel(
      id: id,
      userId: 1,
      name: name,
      targetAmount: target,
      deadline: noDeadline ? null : (deadline ?? DateTime(2027, 5, 1)),
      createdAt: created ?? DateTime(2026, 11, 1),
      savedAmount: saved,
    );

void main() {
  setUpAll(sqfliteFfiInit);

  group('SavingsPlanner', () {
    const SavingsPlanner planner = SavingsPlanner();

    test('kebutuhan per bulan: Rp 8 jt dalam 6 bulan', () {
      final GoalProgress p =
          planner.evaluate(goal(), now: DateTime(2026, 11, 1));

      expect(p.monthsLeft, 6);
      expect(p.requiredPerMonth, closeTo(8000000 / 6, 0.01));
      expect(p.status, GoalStatus.onTrack, reason: 'baru dimulai');
      expect(p.fraction, 0);
    });

    test('sisa target dibagi sisa bulan, bukan target penuh', () {
      final GoalProgress p = planner.evaluate(
        goal(saved: 500000),
        now: DateTime(2027, 2, 1),
      );

      expect(p.monthsLeft, 3);
      expect(p.requiredPerMonth, closeTo(7500000 / 3, 0.01));
    });

    test('tertinggal, sesuai, dan lebih cepat dari jadwal', () {
      final DateTime now = DateTime(2027, 2, 1);

      final GoalProgress behind =
          planner.evaluate(goal(saved: 500000), now: now);
      expect(behind.status, GoalStatus.behind);
      expect(behind.shortfall, greaterThan(3000000));

      final GoalProgress onTrack =
          planner.evaluate(goal(saved: 4000000), now: now);
      expect(onTrack.status, GoalStatus.onTrack);
      expect(onTrack.shortfall, 0);

      final GoalProgress ahead =
          planner.evaluate(goal(saved: 5500000), now: now);
      expect(ahead.status, GoalStatus.ahead);
    });

    test('selesai, lewat tenggat, dan tanpa tenggat', () {
      final GoalProgress done = planner.evaluate(
        goal(saved: 8000000),
        now: DateTime(2027, 1, 1),
      );
      expect(done.status, GoalStatus.completed);
      expect(done.fraction, 1);
      expect(done.requiredPerMonth, isNull);

      final GoalProgress late = planner.evaluate(
        goal(saved: 3000000),
        now: DateTime(2027, 6, 1),
      );
      expect(late.status, GoalStatus.overdue);
      expect(late.requiredPerMonth, 5000000);

      final GoalProgress open = planner.evaluate(
        goal(noDeadline: true, saved: 1000000),
        now: DateTime(2027, 1, 1),
      );
      expect(open.status, GoalStatus.noDeadline);
      expect(open.requiredPerMonth, isNull);
      expect(open.fraction, 0.125);
    });

    test('saldo negatif tidak membuat progres di bawah nol', () {
      final GoalProgress p = planner.evaluate(
        goal(saved: -50000),
        now: DateTime(2026, 11, 1),
      );
      expect(p.fraction, 0);
    });

    List<GoalProgress> twoGoals(DateTime now) => planner.evaluateAll(<SavingsGoalModel>[
          goal(id: 1, name: 'Laptop'),
          goal(
            id: 2,
            name: 'Liburan',
            target: 1500000,
            deadline: DateTime(2027, 1, 31),
          ),
        ], now: now);

    test('saran alokasi: tenggat terdekat dilayani lebih dulu', () {
      final Map<int, double> s = planner.suggestAllocation(
        twoGoals(DateTime(2026, 11, 1)),
        3000000,
      );

      expect(s[2], 500000, reason: 'Liburan 1,5 jt dalam 3 bulan');
      expect(s[1], 1334000, reason: 'Laptop dibulatkan ke atas ke Rp 1.000');
      expect(s.values.fold<double>(0, (double a, double b) => a + b),
          lessThanOrEqualTo(3000000));
    });

    test('saran alokasi tidak pernah melebihi pemasukan', () {
      final Map<int, double> s = planner.suggestAllocation(
        twoGoals(DateTime(2026, 11, 1)),
        800000,
      );

      expect(s[2], 500000);
      expect(s[1], 300000, reason: 'sisa pemasukan');
      expect(s.values.fold<double>(0, (double a, double b) => a + b), 800000);
    });

    test('saran alokasi melewati target selesai dan tanpa tenggat', () {
      final List<GoalProgress> goals = planner.evaluateAll(<SavingsGoalModel>[
        goal(id: 1, saved: 8000000),
        goal(id: 2, noDeadline: true),
        goal(id: 3, name: 'Motor', target: 600000, saved: 100000),
      ], now: DateTime(2026, 11, 1));

      final Map<int, double> s = planner.suggestAllocation(goals, 5000000);

      expect(s.containsKey(1), isFalse);
      expect(s.containsKey(2), isFalse);
      expect(s[3], lessThanOrEqualTo(500000), reason: 'tidak melebihi sisa target');
      expect(planner.suggestAllocation(goals, 0), isEmpty);
    });
  });

  group('Repository (SQLite sungguhan)', () {
    late dynamic db;
    late IncomeRepository incomes;
    late SavingsRepository savings;
    final DateTime now = DateTime(2026, 11, 25);

    setUp(() async {
      db = await openMemoryDatabase();
      await addUser(db, 1);
      await addUser(db, 2);
      final MemoryDatabase mem = MemoryDatabase(db);
      incomes = IncomeRepository(database: mem);
      savings = SavingsRepository(database: mem);
    });
    tearDown(() => db.close());

    IncomeModel income(DateTime date, double amount,
            {int userId = 1, String source = 'Uang saku'}) =>
        IncomeModel(
          userId: userId,
          source: source,
          amount: amount,
          date: date,
          createdAt: now,
        );

    test('pemasukan: simpan, ubah, hapus, dan jumlah per rentang', () async {
      final IncomeModel a =
          await incomes.insert(income(DateTime(2026, 11, 1), 3000000));
      await incomes.insert(income(DateTime(2026, 11, 20), 500000, source: 'Freelance'));
      await incomes.insert(income(DateTime(2026, 10, 1), 2800000));
      await incomes.insert(income(DateTime(2026, 11, 2), 999, userId: 2));

      expect(a.id, isNotNull);
      expect((await incomes.getAll(1)).map((IncomeModel i) => i.amount),
          <double>[500000, 3000000, 2800000],
          reason: 'terbaru dulu, milik pengguna lain tidak ikut');
      expect(
        await incomes.getTotalBetween(1, DateTime(2026, 11), DateTime(2026, 12)),
        3500000,
      );
      expect(
        (await incomes.getBetween(1, DateTime(2026, 10), DateTime(2026, 11)))
            .single
            .amount,
        2800000,
      );

      await incomes.update(a.copyWith(amount: 3100000, source: 'Gaji'));
      final IncomeModel changed =
          (await incomes.getAll(1)).firstWhere((IncomeModel i) => i.id == a.id);
      expect(changed.amount, 3100000);
      expect(changed.source, 'Gaji');

      await incomes.delete(a.id!);
      expect(await incomes.getAll(1), hasLength(2));
    });

    Future<SavingsGoalModel> newGoal(String name, double target,
            {DateTime? deadline, int userId = 1}) =>
        savings.insertGoal(SavingsGoalModel(
          userId: userId,
          name: name,
          targetAmount: target,
          deadline: deadline,
          createdAt: now,
        ));

    SavingsDepositModel deposit(int goalId, double amount, DateTime date,
            {int? incomeId}) =>
        SavingsDepositModel(
          goalId: goalId,
          userId: 1,
          amount: amount,
          date: date,
          incomeId: incomeId,
          createdAt: now,
        );

    test('target: urut tenggat, tanpa tenggat di akhir, dan jumlah tertabung',
        () async {
      final SavingsGoalModel open = await newGoal('Dana darurat', 5000000);
      final SavingsGoalModel laptop =
          await newGoal('Laptop', 8000000, deadline: DateTime(2027, 5, 1));
      final SavingsGoalModel trip =
          await newGoal('Liburan', 1500000, deadline: DateTime(2027, 1, 31));
      await newGoal('Milik orang lain', 1000, userId: 2);

      await savings.insertDeposit(deposit(laptop.id!, 500000, DateTime(2026, 11, 3)));
      await savings.insertDeposit(deposit(laptop.id!, 250000, DateTime(2026, 11, 20)));
      await savings.insertDeposit(deposit(laptop.id!, -100000, DateTime(2026, 11, 21)));

      final List<SavingsGoalModel> goals = await savings.getGoals(1);

      expect(goals.map((SavingsGoalModel g) => g.name),
          <String>['Liburan', 'Laptop', 'Dana darurat']);
      expect(goals[1].savedAmount, 650000, reason: 'setoran dikurangi penarikan');
      expect(goals[0].savedAmount, 0);
      expect(goals[1].remaining, 7350000);
      expect(open.id, isNotNull);
      expect(trip.id, isNotNull);
    });

    test('riwayat setoran terbaru dulu, dan hapus setoran', () async {
      final SavingsGoalModel g = await newGoal('Laptop', 8000000);
      await savings.insertDeposit(deposit(g.id!, 100000, DateTime(2026, 10, 1)));
      await savings.insertDeposit(deposit(g.id!, 200000, DateTime(2026, 11, 1)));

      final List<SavingsDepositModel> list = await savings.getDeposits(g.id!);
      expect(list.map((SavingsDepositModel d) => d.amount), <double>[200000, 100000]);

      await savings.deleteDeposit(list.first.id!);
      expect((await savings.getGoal(g.id!))!.savedAmount, 100000);
    });

    test('menghapus target ikut menghapus setorannya', () async {
      final SavingsGoalModel g = await newGoal('Laptop', 8000000);
      await savings.insertDeposit(deposit(g.id!, 100000, DateTime(2026, 11, 1)));

      await savings.deleteGoal(g.id!);

      expect(await savings.getGoal(g.id!), isNull);
      expect(await db.query('savings_deposits'), isEmpty);
    });

    test('menghapus pemasukan hanya melepas tautan setoran, uang tetap di target',
        () async {
      final IncomeModel inc =
          await incomes.insert(income(DateTime(2026, 11, 1), 3000000));
      final SavingsGoalModel g = await newGoal('Laptop', 8000000);
      await savings.insertDeposit(
          deposit(g.id!, 500000, DateTime(2026, 11, 1), incomeId: inc.id));

      await incomes.delete(inc.id!);

      final List<SavingsDepositModel> list = await savings.getDeposits(g.id!);
      expect(list, hasLength(1));
      expect(list.single.incomeId, isNull);
    });

    test('setoran bersih per rentang tanggal', () async {
      final SavingsGoalModel g = await newGoal('Laptop', 8000000);
      await savings.insertDeposits(<SavingsDepositModel>[
        deposit(g.id!, 500000, DateTime(2026, 11, 3)),
        deposit(g.id!, -100000, DateTime(2026, 11, 28)),
        deposit(g.id!, 700000, DateTime(2026, 10, 15)),
      ]);

      expect(
        await savings.getNetDepositsBetween(1, DateTime(2026, 11), DateTime(2026, 12)),
        400000,
      );
    });

    test('setoran ke target yang tidak ada ditolak (kunci asing)', () async {
      expect(
        () => savings.insertDeposit(deposit(999, 1000, DateTime(2026, 11, 1))),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('IncomeService (pemasukan berulang)', () {
    late dynamic db;
    late IncomeRepository incomes;
    late SavingsRepository savings;
    late IncomeService service;

    setUp(() async {
      db = await openMemoryDatabase();
      await addUser(db, 1);
      final MemoryDatabase mem = MemoryDatabase(db);
      incomes = IncomeRepository(database: mem);
      savings = SavingsRepository(database: mem);
      service = IncomeService(incomes: incomes, savings: savings);
    });
    tearDown(() => db.close());

    Future<RecurringIncomeModel> recurring({
      int day = 1,
      String start = '2026-09',
      int? goalId,
      double? auto,
      double amount = 3000000,
    }) =>
        incomes.insertRecurring(RecurringIncomeModel(
          userId: 1,
          source: 'Uang saku',
          amount: amount,
          dayOfMonth: day,
          startMonth: start,
          autoGoalId: goalId,
          autoAmount: auto,
          createdAt: DateTime(2026, 9, 1),
        ));

    Future<SavingsGoalModel> newGoal(double target) => savings.insertGoal(
          SavingsGoalModel(
            userId: 1,
            name: 'Laptop',
            targetAmount: target,
            deadline: DateTime(2027, 5, 1),
            createdAt: DateTime(2026, 9, 1),
          ),
        );

    test('membuat pemasukan tiap bulan sejak bulan mulai, tidak digandakan',
        () async {
      await recurring();

      final List<IncomeModel> first =
          await service.generateDue(1, now: DateTime(2026, 11, 25));
      expect(first, hasLength(3), reason: 'September, Oktober, November');
      expect(first.map((IncomeModel i) => i.date.month), <int>[9, 10, 11]);
      expect(first.every((IncomeModel i) => i.isAutomatic), isTrue);

      final List<IncomeModel> again =
          await service.generateDue(1, now: DateTime(2026, 11, 26));
      expect(again, isEmpty);
      expect(await incomes.getAll(1), hasLength(3));

      final List<IncomeModel> nextMonth =
          await service.generateDue(1, now: DateTime(2026, 12, 2));
      expect(nextMonth.single.date, DateTime(2026, 12, 1));
    });

    test('bulan berjalan menunggu tanggalnya tiba', () async {
      await recurring(day: 30, start: '2026-11');

      expect(await service.generateDue(1, now: DateTime(2026, 11, 25)), isEmpty);
      final List<IncomeModel> due =
          await service.generateDue(1, now: DateTime(2026, 11, 30));
      expect(due.single.date, DateTime(2026, 11, 30));
    });

    test('tanggal 31 di bulan pendek memakai hari terakhir', () async {
      await recurring(day: 31, start: '2027-02');

      final List<IncomeModel> made =
          await service.generateDue(1, now: DateTime(2027, 3, 5));

      expect(made.first.date, DateTime(2027, 2, 28));
    });

    test('pemasukan berulang yang dimatikan tidak dibuat', () async {
      final RecurringIncomeModel r = await recurring();
      await incomes.setRecurringActive(r.id!, false);

      expect(await service.generateDue(1, now: DateTime(2026, 11, 25)), isEmpty);
    });

    test('otomatis menyisihkan ke target tiap pemasukan dibuat', () async {
      final SavingsGoalModel g = await newGoal(8000000);
      await recurring(goalId: g.id, auto: 500000);

      final List<IncomeModel> made =
          await service.generateDue(1, now: DateTime(2026, 11, 25));

      final List<SavingsDepositModel> deposits = await savings.getDeposits(g.id!);
      expect(deposits, hasLength(3));
      expect(deposits.every((SavingsDepositModel d) => d.amount == 500000), isTrue);
      expect(deposits.map((SavingsDepositModel d) => d.incomeId).toSet(),
          made.map((IncomeModel i) => i.id).toSet(),
          reason: 'setiap setoran tertaut ke pemasukan asalnya');
      expect((await savings.getGoal(g.id!))!.savedAmount, 1500000);
    });

    test('setoran otomatis berhenti saat target tercapai', () async {
      final SavingsGoalModel g = await newGoal(600000);
      await recurring(goalId: g.id, auto: 500000);

      await service.generateDue(1, now: DateTime(2026, 11, 25));

      final List<SavingsDepositModel> deposits = await savings.getDeposits(g.id!);
      expect(deposits.map((SavingsDepositModel d) => d.amount).toList()..sort(),
          <double>[100000, 500000]);
      expect((await savings.getGoal(g.id!))!.isCompleted, isTrue);
    });

    test('setoran otomatis tidak melebihi pemasukannya', () async {
      final SavingsGoalModel g = await newGoal(8000000);
      await recurring(goalId: g.id, auto: 900000, amount: 400000);

      await service.generateDue(1, now: DateTime(2026, 9, 5));

      expect((await savings.getDeposits(g.id!)).single.amount, 400000);
    });

    test('target yang sudah dihapus tidak membuat pemasukan gagal', () async {
      final SavingsGoalModel g = await newGoal(8000000);
      await recurring(goalId: g.id, auto: 500000);
      await savings.deleteGoal(g.id!);

      final List<IncomeModel> made =
          await service.generateDue(1, now: DateTime(2026, 11, 25));

      expect(made, hasLength(3));
    });

    test('dua panggilan bersamaan tidak membuat pemasukan ganda', () async {
      await recurring();

      final List<List<IncomeModel>> results = await Future.wait(
        <Future<List<IncomeModel>>>[
          service.generateDue(1, now: DateTime(2026, 11, 25)),
          service.generateDue(1, now: DateTime(2026, 11, 25)),
        ],
      );

      expect(results[0], hasLength(3));
      expect(await incomes.getAll(1), hasLength(3));
    });
  });

  group('CashFlowService', () {
    late dynamic db;
    late CashFlowService service;
    late IncomeRepository incomes;
    late SavingsRepository savings;

    setUp(() async {
      db = await openMemoryDatabase();
      await addUser(db, 1);
      final MemoryDatabase mem = MemoryDatabase(db);
      incomes = IncomeRepository(database: mem);
      savings = SavingsRepository(database: mem);
      service = CashFlowService(
        incomes: incomes,
        savings: savings,
        transactions: TransactionRepository(database: mem),
      );
    });
    tearDown(() => db.close());

    test('sisa = pemasukan - pengeluaran - tabungan (contoh Oktober)', () async {
      await incomes.insert(IncomeModel(
        userId: 1,
        source: 'Uang saku',
        amount: 3000000,
        date: DateTime(2026, 10, 1),
        createdAt: DateTime(2026, 10, 1),
      ));
      await addExpense(db, userId: 1, date: DateTime(2026, 10, 5), total: 1200000);
      await addExpense(db, userId: 1, date: DateTime(2026, 10, 20), total: 800000);
      final SavingsGoalModel g = await savings.insertGoal(SavingsGoalModel(
        userId: 1,
        name: 'Laptop',
        targetAmount: 8000000,
        createdAt: DateTime(2026, 10, 1),
      ));
      await savings.insertDeposit(SavingsDepositModel(
        goalId: g.id!,
        userId: 1,
        amount: 600000,
        date: DateTime(2026, 10, 1),
        createdAt: DateTime(2026, 10, 1),
      ));

      final CashFlow flow =
          await service.forRange(1, DateTime(2026, 10), DateTime(2026, 11));

      expect(flow.income, 3000000);
      expect(flow.expense, 2000000);
      expect(flow.saved, 600000);
      expect(flow.free, 400000);
      expect(flow.isDeficit, isFalse);
      expect(flow.spentRatio, closeTo(2 / 3, 1e-9));
    });

    test('penarikan tabungan mengembalikan uang ke sisa', () async {
      await incomes.insert(IncomeModel(
        userId: 1,
        source: 'Gaji',
        amount: 1000000,
        date: DateTime(2026, 11, 1),
        createdAt: DateTime(2026, 11, 1),
      ));
      final SavingsGoalModel g = await savings.insertGoal(SavingsGoalModel(
        userId: 1,
        name: 'Dana',
        targetAmount: 5000000,
        createdAt: DateTime(2026, 11, 1),
      ));
      await savings.insertDeposits(<SavingsDepositModel>[
        SavingsDepositModel(
            goalId: g.id!, userId: 1, amount: 600000, date: DateTime(2026, 11, 2), createdAt: DateTime(2026, 11, 2)),
        SavingsDepositModel(
            goalId: g.id!, userId: 1, amount: -200000, date: DateTime(2026, 11, 20), createdAt: DateTime(2026, 11, 20)),
      ]);

      final CashFlow flow =
          await service.forRange(1, DateTime(2026, 11), DateTime(2026, 12));

      expect(flow.saved, 400000);
      expect(flow.free, 600000);
    });

    test('pengeluaran melebihi pemasukan = defisit', () async {
      await incomes.insert(IncomeModel(
        userId: 1,
        source: 'Uang saku',
        amount: 1000000,
        date: DateTime(2026, 11, 1),
        createdAt: DateTime(2026, 11, 1),
      ));
      await addExpense(db, userId: 1, date: DateTime(2026, 11, 3), total: 1500000);

      final CashFlow flow =
          await service.forRange(1, DateTime(2026, 11), DateTime(2026, 12));

      expect(flow.free, -500000);
      expect(flow.isDeficit, isTrue);
    });

    test('enam bulan terakhir, terlama dulu, bulan tanpa data bernilai nol',
        () async {
      await incomes.insert(IncomeModel(
        userId: 1,
        source: 'Uang saku',
        amount: 3000000,
        date: DateTime(2026, 11, 1),
        createdAt: DateTime(2026, 11, 1),
      ));
      await addExpense(db, userId: 1, date: DateTime(2026, 8, 10), total: 700000);

      final List<MonthCashFlow> months =
          await service.lastMonths(1, 6, now: DateTime(2026, 11, 25));

      expect(months, hasLength(6));
      expect(months.first.month, DateTime(2026, 6));
      expect(months.last.month, DateTime(2026, 11));
      expect(months[2].flow.expense, 700000);
      expect(months[0].flow.hasData, isFalse);
      expect(months.last.flow.income, 3000000);
    });

    test('data pengguna lain tidak ikut', () async {
      await addUser(db, 2);
      await incomes.insert(IncomeModel(
        userId: 2,
        source: 'Gaji',
        amount: 9000000,
        date: DateTime(2026, 11, 1),
        createdAt: DateTime(2026, 11, 1),
      ));

      final CashFlow flow =
          await service.forRange(1, DateTime(2026, 11), DateTime(2026, 12));
      expect(flow.hasData, isFalse);
    });
  });

  group('Migrasi basis data v7 -> v8', () {
    test('tabel baru dibuat tanpa mengubah data lama', () async {
      final Database db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (Database d) => d.execute('PRAGMA foreign_keys = ON'),
          onCreate: (Database d, int v) async {
            // Skema versi 7: semua tabel kecuali empat tabel baru.
            const List<String> newTables = <String>[
              'CREATE TABLE incomes',
              'CREATE TABLE recurring_incomes',
              'CREATE TABLE savings_goals',
              'CREATE TABLE savings_deposits',
            ];
            for (final String sql in DatabaseSchema.createStatements) {
              if (newTables.any(sql.contains)) continue;
              await d.execute(sql);
            }
          },
        ),
      );
      await addUser(db, 1);
      expect(
        (await db.rawQuery("SELECT name FROM sqlite_master WHERE name = 'incomes'")),
        isEmpty,
      );

      for (final String statement in DatabaseSchema.upgradeToV8) {
        await db.execute(statement);
      }

      final List<Map<String, Object?>> tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name IN ('incomes','recurring_incomes','savings_goals','savings_deposits')");
      expect(tables, hasLength(4));
      expect((await db.query('users')), hasLength(1), reason: 'data lama utuh');

      final IncomeRepository repo = IncomeRepository(database: MemoryDatabase(db));
      await repo.insert(IncomeModel(
        userId: 1,
        source: 'Gaji',
        amount: 1,
        date: DateTime(2026, 11, 1),
        createdAt: DateTime(2026, 11, 1),
      ));
      expect(await repo.getAll(1), hasLength(1));
      await db.close();
    });
  });
}
