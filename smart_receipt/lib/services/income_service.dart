import 'dart:math' as math;

import '../core/utils/month_utils.dart';
import '../data/models/income_model.dart';
import '../data/models/savings_models.dart';
import '../data/repositories/income_repository.dart';
import '../data/repositories/savings_repository.dart';

/// Membuat pemasukan bulanan dari pemasukan berulang yang sudah jatuh tempo,
/// dan (bila diatur) langsung menyisihkannya ke target tabungan.
class IncomeService {
  IncomeService({
    required IncomeRepository incomes,
    required SavingsRepository savings,
  })  : _incomes = incomes,
        _savings = savings;

  final IncomeRepository _incomes;
  final SavingsRepository _savings;

  Future<List<IncomeModel>>? _running;

  /// Mengembalikan pemasukan yang baru dibuat. Bulan yang sudah dibuat tidak
  /// digandakan karena posisinya dicatat di `last_generated`. Panggilan yang
  /// bersamaan (mis. saat aplikasi dibuka dan layar Pemasukan terbuka)
  /// berbagi satu proses agar tidak terjadi pemasukan ganda.
  Future<List<IncomeModel>> generateDue(int userId, {DateTime? now}) {
    final Future<List<IncomeModel>>? running = _running;
    if (running != null) return running;
    final Future<List<IncomeModel>> job = _generate(userId, now);
    _running = job;
    return job.whenComplete(() => _running = null);
  }

  Future<List<IncomeModel>> _generate(int userId, DateTime? now) async {
    final DateTime current = now ?? DateTime.now();
    final String currentKey = MonthUtils.key(current);
    final List<IncomeModel> created = <IncomeModel>[];

    for (final RecurringIncomeModel rec
        in await _incomes.getRecurring(userId)) {
      final int? recId = rec.id;
      if (!rec.isActive || recId == null) continue;

      DateTime cursor = MonthUtils.parse(rec.lastGenerated ?? rec.startMonth);
      if (rec.lastGenerated != null) {
        cursor = DateTime(cursor.year, cursor.month + 1);
      }

      while (MonthUtils.key(cursor).compareTo(currentKey) <= 0) {
        final int day = math.min(
          rec.dayOfMonth,
          MonthUtils.daysIn(cursor.year, cursor.month),
        );
        final DateTime date = DateTime(cursor.year, cursor.month, day);
        // Bulan berjalan menunggu sampai tanggalnya tiba.
        if (date.isAfter(current)) break;

        final IncomeModel income = await _incomes.insert(
          IncomeModel(
            userId: userId,
            source: rec.source,
            amount: rec.amount,
            date: date,
            notes: rec.notes ?? 'Otomatis (pemasukan berulang)',
            recurringId: recId,
            createdAt: current,
          ),
        );
        await _incomes.setRecurringLastGenerated(recId, MonthUtils.key(cursor));
        created.add(income);
        await _autoAllocate(rec, income, current);
        cursor = DateTime(cursor.year, cursor.month + 1);
      }
    }
    return created;
  }

  /// Menyetor otomatis ke target yang diatur pada pemasukan berulang. Target
  /// yang sudah tercapai atau sudah dihapus dilewati.
  Future<void> _autoAllocate(
    RecurringIncomeModel rec,
    IncomeModel income,
    DateTime now,
  ) async {
    final int? goalId = rec.autoGoalId;
    final int? incomeId = income.id;
    if (!rec.hasAutoAllocation || goalId == null || incomeId == null) return;

    final SavingsGoalModel? goal = await _savings.getGoal(goalId);
    if (goal == null || goal.isCompleted) return;

    final double amount = math.min(
      math.min(rec.autoAmount!, income.amount),
      goal.remaining,
    );
    if (amount < 1) return;

    await _savings.insertDeposit(
      SavingsDepositModel(
        goalId: goalId,
        userId: income.userId,
        amount: amount,
        date: income.date,
        incomeId: incomeId,
        notes: 'Otomatis dari ${income.source}',
        createdAt: now,
      ),
    );
  }
}
