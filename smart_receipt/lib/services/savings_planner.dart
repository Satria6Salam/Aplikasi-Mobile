import '../data/models/savings_models.dart';

/// Posisi sebuah target terhadap jadwalnya.
enum GoalStatus {
  /// Tabungan sudah mencapai target.
  completed,

  /// Tenggat lewat dan target belum tercapai.
  overdue,

  /// Tanpa tenggat: tidak ada jadwal yang bisa dibandingkan.
  noDeadline,

  /// Lebih cepat dari jadwal.
  ahead,

  /// Sesuai jadwal.
  onTrack,

  /// Tertinggal dari jadwal.
  behind,
}

/// Hasil evaluasi sebuah target pada tanggal tertentu.
class GoalProgress {
  const GoalProgress({
    required this.goal,
    required this.fraction,
    required this.status,
    required this.monthsLeft,
    required this.requiredPerMonth,
    required this.expectedByNow,
    required this.shortfall,
  });

  final SavingsGoalModel goal;

  /// Progres 0..1.
  final double fraction;
  final GoalStatus status;

  /// Sisa bulan sampai tenggat (dibulatkan ke atas, minimal 1); null tanpa tenggat.
  final int? monthsLeft;

  /// Setoran per bulan agar target tepat waktu; null tanpa tenggat atau bila selesai.
  final double? requiredPerMonth;

  /// Jumlah yang seharusnya sudah terkumpul menurut jadwal lurus.
  final double expectedByNow;

  /// Kekurangan dari jadwal (0 bila tidak tertinggal).
  final double shortfall;

  bool get isActive => status != GoalStatus.completed;
}

/// Menghitung kebutuhan per bulan, status jadwal, dan saran alokasi
/// pemasukan ke target-target tabungan.
class SavingsPlanner {
  const SavingsPlanner();

  /// Rata-rata hari dalam sebulan.
  static const double _daysPerMonth = 30.4375;

  /// Toleransi sebelum dianggap lebih cepat atau tertinggal dari jadwal.
  static const double _tolerance = 0.05;

  GoalProgress evaluate(SavingsGoalModel goal, {DateTime? now}) {
    final DateTime today = _day(now ?? DateTime.now());
    final double target = goal.targetAmount;
    final double saved = goal.savedAmount < 0 ? 0 : goal.savedAmount;
    final double fraction =
        target <= 0 ? 0 : (saved / target).clamp(0.0, 1.0).toDouble();

    if (goal.isCompleted) {
      return GoalProgress(
        goal: goal,
        fraction: 1,
        status: GoalStatus.completed,
        monthsLeft: null,
        requiredPerMonth: null,
        expectedByNow: target,
        shortfall: 0,
      );
    }

    final DateTime? due = goal.deadline == null ? null : _day(goal.deadline!);
    if (due == null) {
      return GoalProgress(
        goal: goal,
        fraction: fraction,
        status: GoalStatus.noDeadline,
        monthsLeft: null,
        requiredPerMonth: null,
        expectedByNow: 0,
        shortfall: 0,
      );
    }

    if (due.isBefore(today)) {
      return GoalProgress(
        goal: goal,
        fraction: fraction,
        status: GoalStatus.overdue,
        monthsLeft: 0,
        requiredPerMonth: goal.remaining,
        expectedByNow: target,
        shortfall: goal.remaining,
      );
    }

    final int daysLeft = due.difference(today).inDays;
    final int monthsLeft = _monthsFromDays(daysLeft);
    final double perMonth = goal.remaining / monthsLeft;

    // Jadwal lurus dari tanggal dibuat sampai tenggat.
    final DateTime start = _day(goal.createdAt);
    final int totalDays = due.difference(start).inDays;
    double expected = 0;
    if (totalDays > 0) {
      final int elapsed = today.difference(start).inDays;
      expected = target * (elapsed / totalDays).clamp(0.0, 1.0);
    }

    final GoalStatus status;
    if (expected <= 0) {
      status = GoalStatus.onTrack;
    } else if (saved >= expected * (1 + _tolerance)) {
      status = GoalStatus.ahead;
    } else if (saved >= expected * (1 - _tolerance)) {
      status = GoalStatus.onTrack;
    } else {
      status = GoalStatus.behind;
    }

    return GoalProgress(
      goal: goal,
      fraction: fraction,
      status: status,
      monthsLeft: monthsLeft,
      requiredPerMonth: perMonth,
      expectedByNow: expected,
      // Kekurangan hanya dilaporkan bila benar-benar tertinggal; selisih kecil
      // dalam toleransi dianggap sesuai jadwal.
      shortfall: status == GoalStatus.behind ? expected - saved : 0,
    );
  }

  List<GoalProgress> evaluateAll(List<SavingsGoalModel> goals,
      {DateTime? now}) {
    return <GoalProgress>[
      for (final SavingsGoalModel g in goals) evaluate(g, now: now),
    ];
  }

  /// Saran pembagian sebuah pemasukan ke target yang masih berjalan.
  ///
  /// Tiap target mendapat kebutuhan per bulannya (tidak lebih dari sisa
  /// targetnya); target dengan tenggat paling dekat dilayani lebih dulu, dan
  /// total tidak pernah melebihi [incomeAmount]. Target tanpa tenggat tidak
  /// diberi saran. Hasil dibulatkan ke atas ke kelipatan Rp 1.000 bila masih
  /// muat dalam sisa pemasukan.
  Map<int, double> suggestAllocation(
    List<GoalProgress> goals,
    double incomeAmount,
  ) {
    final Map<int, double> result = <int, double>{};
    if (incomeAmount <= 0) return result;

    final List<GoalProgress> active = goals
        .where((GoalProgress g) =>
            g.goal.id != null && g.isActive && (g.requiredPerMonth ?? 0) > 0)
        .toList()
      ..sort((GoalProgress a, GoalProgress b) {
        final DateTime? da = a.goal.deadline;
        final DateTime? db = b.goal.deadline;
        if (da == null || db == null) return da == null ? 1 : -1;
        return da.compareTo(db);
      });

    double left = incomeAmount;
    for (final GoalProgress g in active) {
      if (left <= 0) break;
      double want = g.requiredPerMonth!;
      if (want > g.goal.remaining) want = g.goal.remaining;
      final double rounded = (want / 1000).ceilToDouble() * 1000;
      if (rounded <= g.goal.remaining && rounded <= left) want = rounded;
      if (want > left) want = left;
      if (want >= 1) {
        result[g.goal.id!] = want;
        left -= want;
      }
    }
    return result;
  }

  // ------------------------------------------------------------- pembantu

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Hari -> bulan, dibulatkan ke atas dan minimal 1.
  static int _monthsFromDays(int days) {
    final int months = (days / _daysPerMonth).ceil();
    return months < 1 ? 1 : months;
  }
}
