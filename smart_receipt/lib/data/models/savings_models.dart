import '../../core/constants/db_constants.dart';
import '../../core/utils/db_date_utils.dart';

/// Target tabungan, mis. "Laptop baru" Rp 8.000.000 sebelum April.
class SavingsGoalModel {
  const SavingsGoalModel({
    this.id,
    required this.userId,
    required this.name,
    required this.targetAmount,
    this.deadline,
    this.notes,
    required this.createdAt,
    this.savedAmount = 0,
  });

  final int? id;
  final int userId;
  final String name;
  final double targetAmount;

  /// Tenggat; null berarti tanpa batas waktu.
  final DateTime? deadline;
  final String? notes;
  final DateTime createdAt;

  /// Total yang sudah ditabung (setoran dikurangi penarikan). Tidak disimpan
  /// di tabel; dihitung saat query digabung dengan `savings_deposits`.
  final double savedAmount;

  double get remaining {
    final double left = targetAmount - savedAmount;
    return left < 0 ? 0 : left;
  }

  bool get isCompleted => targetAmount > 0 && savedAmount >= targetAmount;

  factory SavingsGoalModel.fromMap(Map<String, Object?> map) {
    return SavingsGoalModel(
      id: map[GoalCols.id] as int?,
      userId: map[GoalCols.userId] as int? ?? 0,
      name: map[GoalCols.name] as String? ?? '',
      targetAmount: (map[GoalCols.targetAmount] as num?)?.toDouble() ?? 0,
      deadline: DbDateUtils.tryParse(map[GoalCols.deadline]),
      notes: map[GoalCols.notes] as String?,
      createdAt: DbDateUtils.parseOrNow(map[GoalCols.createdAt]),
      savedAmount: (map['saved_amount'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, Object?> toMap() {
    final DateTime? due = deadline;
    return <String, Object?>{
      if (id != null) GoalCols.id: id,
      GoalCols.userId: userId,
      GoalCols.name: name,
      GoalCols.targetAmount: targetAmount,
      GoalCols.deadline: due == null ? null : DbDateUtils.dateToDb(due),
      GoalCols.notes: notes,
      GoalCols.createdAt: DbDateUtils.dateTimeToDb(createdAt),
    };
  }

  SavingsGoalModel copyWith({
    int? id,
    String? name,
    double? targetAmount,
    DateTime? deadline,
    bool clearDeadline = false,
    String? notes,
    double? savedAmount,
  }) {
    return SavingsGoalModel(
      id: id ?? this.id,
      userId: userId,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      notes: notes ?? this.notes,
      createdAt: createdAt,
      savedAmount: savedAmount ?? this.savedAmount,
    );
  }
}

/// Satu setoran (positif) atau penarikan (negatif) pada sebuah target.
class SavingsDepositModel {
  const SavingsDepositModel({
    this.id,
    required this.goalId,
    required this.userId,
    required this.amount,
    required this.date,
    this.incomeId,
    this.notes,
    required this.createdAt,
  });

  final int? id;
  final int goalId;
  final int userId;

  /// Positif = setoran, negatif = penarikan.
  final double amount;
  final DateTime date;

  /// Pemasukan asal bila disisihkan saat mencatat pemasukan.
  final int? incomeId;
  final String? notes;
  final DateTime createdAt;

  bool get isWithdrawal => amount < 0;

  factory SavingsDepositModel.fromMap(Map<String, Object?> map) {
    return SavingsDepositModel(
      id: map[DepositCols.id] as int?,
      goalId: map[DepositCols.goalId] as int? ?? 0,
      userId: map[DepositCols.userId] as int? ?? 0,
      amount: (map[DepositCols.amount] as num?)?.toDouble() ?? 0,
      date: DbDateUtils.parseOrNow(map[DepositCols.depositDate]),
      incomeId: map[DepositCols.incomeId] as int?,
      notes: map[DepositCols.notes] as String?,
      createdAt: DbDateUtils.parseOrNow(map[DepositCols.createdAt]),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) DepositCols.id: id,
      DepositCols.goalId: goalId,
      DepositCols.userId: userId,
      DepositCols.amount: amount,
      DepositCols.depositDate: DbDateUtils.dateToDb(date),
      DepositCols.incomeId: incomeId,
      DepositCols.notes: notes,
      DepositCols.createdAt: DbDateUtils.dateTimeToDb(createdAt),
    };
  }
}
