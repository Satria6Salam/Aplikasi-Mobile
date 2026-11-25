import '../core/utils/month_utils.dart';
import '../data/repositories/income_repository.dart';
import '../data/repositories/savings_repository.dart';
import '../data/repositories/transaction_repository.dart';

/// Arus kas satu periode: uang masuk, uang belanja, dan uang yang disisihkan.
///
/// Setoran tabungan BUKAN pengeluaran: ia tidak masuk grafik belanja atau
/// anggaran, hanya mengurangi sisa uang bebas. Penarikan tabungan
/// (setoran negatif) mengembalikan uang ke sisa.
class CashFlow {
  const CashFlow({
    required this.income,
    required this.expense,
    required this.saved,
  });

  static const CashFlow zero = CashFlow(income: 0, expense: 0, saved: 0);

  final double income;
  final double expense;

  /// Setoran bersih ke tabungan (setoran dikurangi penarikan).
  final double saved;

  /// Sisa uang bebas: pemasukan - pengeluaran - tabungan.
  double get free => income - expense - saved;

  bool get isDeficit => free < -0.5;
  bool get hasData => income != 0 || expense != 0 || saved != 0;

  /// Bagian pemasukan yang dibelanjakan (0 bila tidak ada pemasukan).
  double get spentRatio => income > 0 ? expense / income : 0;
}

/// Arus kas sebuah bulan (untuk grafik tren).
class MonthCashFlow {
  const MonthCashFlow({required this.month, required this.flow});

  /// Tanggal 1 pada bulan tersebut.
  final DateTime month;
  final CashFlow flow;
}

class CashFlowService {
  CashFlowService({
    required IncomeRepository incomes,
    required SavingsRepository savings,
    required TransactionRepository transactions,
  })  : _incomes = incomes,
        _savings = savings,
        _transactions = transactions;

  final IncomeRepository _incomes;
  final SavingsRepository _savings;
  final TransactionRepository _transactions;

  Future<CashFlow> forRange(
    int userId,
    DateTime start,
    DateTime endExclusive,
  ) async {
    final double income =
        await _incomes.getTotalBetween(userId, start, endExclusive);
    final double expense =
        await _transactions.getTotalBetween(userId, start, endExclusive);
    final double saved =
        await _savings.getNetDepositsBetween(userId, start, endExclusive);
    return CashFlow(income: income, expense: expense, saved: saved);
  }

  /// [count] bulan terakhir sampai bulan [now], terlama lebih dulu.
  Future<List<MonthCashFlow>> lastMonths(
    int userId,
    int count, {
    DateTime? now,
  }) async {
    final DateTime current = now ?? DateTime.now();
    final List<MonthCashFlow> result = <MonthCashFlow>[];
    for (int i = count - 1; i >= 0; i--) {
      final DateTime month = DateTime(current.year, current.month - i);
      result.add(
        MonthCashFlow(
          month: month,
          flow: await forRange(
            userId,
            MonthUtils.startOf(month),
            MonthUtils.endExclusive(month),
          ),
        ),
      );
    }
    return result;
  }
}
