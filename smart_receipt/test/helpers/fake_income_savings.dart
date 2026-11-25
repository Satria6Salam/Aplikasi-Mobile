import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/core/utils/month_utils.dart';
import 'package:smart_receipt/data/models/income_model.dart';
import 'package:smart_receipt/data/models/savings_models.dart';
import 'package:smart_receipt/data/repositories/income_repository.dart';
import 'package:smart_receipt/data/repositories/savings_repository.dart';
import 'package:smart_receipt/data/repositories/transaction_repository.dart';

/// Repository pemasukan di memori (perilaku sama dengan versi SQLite).
class FakeIncomeRepository extends Fake implements IncomeRepository {
  final List<IncomeModel> incomes = <IncomeModel>[];
  final List<RecurringIncomeModel> recurring = <RecurringIncomeModel>[];
  int _nextId = 1;
  bool failInsert = false;

  @override
  Future<List<IncomeModel>> getAll(int userId, {int limit = 1000}) async {
    final List<IncomeModel> list =
        incomes.where((IncomeModel i) => i.userId == userId).toList()
          ..sort((IncomeModel a, IncomeModel b) {
            final int byDate = b.date.compareTo(a.date);
            return byDate != 0 ? byDate : (b.id ?? 0).compareTo(a.id ?? 0);
          });
    return list.take(limit).toList();
  }

  @override
  Future<double> getTotalBetween(
    int userId,
    DateTime start,
    DateTime endExclusive,
  ) async {
    return incomes
        .where((IncomeModel i) =>
            i.userId == userId &&
            !i.date.isBefore(start) &&
            i.date.isBefore(endExclusive))
        .fold<double>(0, (double s, IncomeModel i) => s + i.amount);
  }

  @override
  Future<IncomeModel> insert(IncomeModel income) async {
    if (failInsert) throw StateError('gagal');
    final IncomeModel saved = income.copyWith(id: _nextId++);
    incomes.add(saved);
    return saved;
  }

  @override
  Future<void> update(IncomeModel income) async {
    final int at = incomes.indexWhere((IncomeModel i) => i.id == income.id);
    if (at >= 0) incomes[at] = income;
  }

  @override
  Future<void> delete(int id) async =>
      incomes.removeWhere((IncomeModel i) => i.id == id);

  @override
  Future<List<RecurringIncomeModel>> getRecurring(int userId) async =>
      recurring.where((RecurringIncomeModel r) => r.userId == userId).toList();

  @override
  Future<RecurringIncomeModel> insertRecurring(
      RecurringIncomeModel model) async {
    final RecurringIncomeModel saved = model.copyWith(id: _nextId++);
    recurring.add(saved);
    return saved;
  }

  @override
  Future<void> setRecurringActive(int id, bool isActive) async {
    final int at = recurring.indexWhere((RecurringIncomeModel r) => r.id == id);
    if (at < 0) return;
    final RecurringIncomeModel r = recurring[at];
    recurring[at] = RecurringIncomeModel(
      id: r.id,
      userId: r.userId,
      source: r.source,
      amount: r.amount,
      dayOfMonth: r.dayOfMonth,
      startMonth: r.startMonth,
      lastGenerated: r.lastGenerated,
      isActive: isActive,
      autoGoalId: r.autoGoalId,
      autoAmount: r.autoAmount,
      notes: r.notes,
      createdAt: r.createdAt,
    );
  }

  @override
  Future<void> setRecurringLastGenerated(int id, String monthKey) async {
    final int at = recurring.indexWhere((RecurringIncomeModel r) => r.id == id);
    if (at < 0) return;
    final RecurringIncomeModel r = recurring[at];
    recurring[at] = RecurringIncomeModel(
      id: r.id,
      userId: r.userId,
      source: r.source,
      amount: r.amount,
      dayOfMonth: r.dayOfMonth,
      startMonth: r.startMonth,
      lastGenerated: monthKey,
      isActive: r.isActive,
      autoGoalId: r.autoGoalId,
      autoAmount: r.autoAmount,
      notes: r.notes,
      createdAt: r.createdAt,
    );
  }

  @override
  Future<void> deleteRecurring(int id) async =>
      recurring.removeWhere((RecurringIncomeModel r) => r.id == id);
}

/// Repository tabungan di memori.
class FakeSavingsRepository extends Fake implements SavingsRepository {
  final List<SavingsGoalModel> goals = <SavingsGoalModel>[];
  final List<SavingsDepositModel> deposits = <SavingsDepositModel>[];
  int _nextId = 1;

  SavingsGoalModel _withSaved(SavingsGoalModel g) => g.copyWith(
        savedAmount: deposits
            .where((SavingsDepositModel d) => d.goalId == g.id)
            .fold<double>(0, (double s, SavingsDepositModel d) => s + d.amount),
      );

  @override
  Future<List<SavingsGoalModel>> getGoals(int userId) async {
    final List<SavingsGoalModel> list = goals
        .where((SavingsGoalModel g) => g.userId == userId)
        .map(_withSaved)
        .toList()
      ..sort((SavingsGoalModel a, SavingsGoalModel b) {
        if (a.deadline == null || b.deadline == null) {
          if (a.deadline == null && b.deadline == null) {
            return (a.id ?? 0).compareTo(b.id ?? 0);
          }
          return a.deadline == null ? 1 : -1;
        }
        return a.deadline!.compareTo(b.deadline!);
      });
    return list;
  }

  @override
  Future<SavingsGoalModel?> getGoal(int id) async {
    for (final SavingsGoalModel g in goals) {
      if (g.id == id) return _withSaved(g);
    }
    return null;
  }

  @override
  Future<SavingsGoalModel> insertGoal(SavingsGoalModel goal) async {
    final SavingsGoalModel saved = goal.copyWith(id: _nextId++);
    goals.add(saved);
    return saved;
  }

  @override
  Future<void> updateGoal(SavingsGoalModel goal) async {
    final int at = goals.indexWhere((SavingsGoalModel g) => g.id == goal.id);
    if (at >= 0) goals[at] = goal;
  }

  @override
  Future<void> deleteGoal(int id) async {
    goals.removeWhere((SavingsGoalModel g) => g.id == id);
    deposits.removeWhere((SavingsDepositModel d) => d.goalId == id);
  }

  @override
  Future<List<SavingsDepositModel>> getDeposits(int goalId) async {
    final List<SavingsDepositModel> list =
        deposits.where((SavingsDepositModel d) => d.goalId == goalId).toList()
          ..sort((SavingsDepositModel a, SavingsDepositModel b) {
            final int byDate = b.date.compareTo(a.date);
            return byDate != 0 ? byDate : (b.id ?? 0).compareTo(a.id ?? 0);
          });
    return list;
  }

  @override
  Future<void> insertDeposit(SavingsDepositModel d) => insertDeposits(
        <SavingsDepositModel>[d],
      );

  @override
  Future<void> insertDeposits(List<SavingsDepositModel> list) async {
    for (final SavingsDepositModel d in list) {
      deposits.add(SavingsDepositModel(
        id: _nextId++,
        goalId: d.goalId,
        userId: d.userId,
        amount: d.amount,
        date: d.date,
        incomeId: d.incomeId,
        notes: d.notes,
        createdAt: d.createdAt,
      ));
    }
  }

  @override
  Future<void> deleteDeposit(int id) async =>
      deposits.removeWhere((SavingsDepositModel d) => d.id == id);

  @override
  Future<double> getNetDepositsBetween(
    int userId,
    DateTime start,
    DateTime endExclusive,
  ) async {
    return deposits
        .where((SavingsDepositModel d) =>
            d.userId == userId &&
            !d.date.isBefore(start) &&
            d.date.isBefore(endExclusive))
        .fold<double>(0, (double s, SavingsDepositModel d) => s + d.amount);
  }
}

/// Pengeluaran per bulan (kunci "yyyy-MM") untuk arus kas.
class FakeExpenseRepository extends Fake implements TransactionRepository {
  final Map<String, double> expenseByMonth = <String, double>{};

  @override
  Future<double> getTotalBetween(
    int userId,
    DateTime start,
    DateTime endExclusive,
  ) async {
    double total = 0;
    DateTime cursor = DateTime(start.year, start.month);
    while (cursor.isBefore(endExclusive)) {
      total += expenseByMonth[MonthUtils.key(cursor)] ?? 0;
      cursor = DateTime(cursor.year, cursor.month + 1);
    }
    return total;
  }
}
