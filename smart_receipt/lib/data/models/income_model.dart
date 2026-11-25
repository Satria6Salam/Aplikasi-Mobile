import '../../core/constants/db_constants.dart';
import '../../core/utils/db_date_utils.dart';

/// Satu pemasukan (uang saku, gaji, freelance, hadiah, dst.).
class IncomeModel {
  const IncomeModel({
    this.id,
    required this.userId,
    required this.source,
    required this.amount,
    required this.date,
    this.notes,
    this.recurringId,
    required this.createdAt,
  });

  final int? id;
  final int userId;

  /// Sumber pemasukan, mis. "Uang saku".
  final String source;
  final double amount;
  final DateTime date;
  final String? notes;

  /// Terisi bila dibuat otomatis dari pemasukan berulang.
  final int? recurringId;
  final DateTime createdAt;

  bool get isAutomatic => recurringId != null;

  factory IncomeModel.fromMap(Map<String, Object?> map) {
    return IncomeModel(
      id: map[IncomeCols.id] as int?,
      userId: map[IncomeCols.userId] as int? ?? 0,
      source: map[IncomeCols.source] as String? ?? '',
      amount: (map[IncomeCols.amount] as num?)?.toDouble() ?? 0,
      date: DbDateUtils.parseOrNow(map[IncomeCols.incomeDate]),
      notes: map[IncomeCols.notes] as String?,
      recurringId: map[IncomeCols.recurringId] as int?,
      createdAt: DbDateUtils.parseOrNow(map[IncomeCols.createdAt]),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) IncomeCols.id: id,
      IncomeCols.userId: userId,
      IncomeCols.source: source,
      IncomeCols.amount: amount,
      IncomeCols.incomeDate: DbDateUtils.dateToDb(date),
      IncomeCols.notes: notes,
      IncomeCols.recurringId: recurringId,
      IncomeCols.createdAt: DbDateUtils.dateTimeToDb(createdAt),
    };
  }

  IncomeModel copyWith({
    int? id,
    String? source,
    double? amount,
    DateTime? date,
    String? notes,
    int? recurringId,
  }) {
    return IncomeModel(
      id: id ?? this.id,
      userId: userId,
      source: source ?? this.source,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      recurringId: recurringId ?? this.recurringId,
      createdAt: createdAt,
    );
  }
}

/// Pemasukan yang berulang tiap bulan (mis. uang saku tanggal 1).
/// Pemasukan bulanannya dibuat otomatis saat aplikasi dibuka.
class RecurringIncomeModel {
  const RecurringIncomeModel({
    this.id,
    required this.userId,
    required this.source,
    required this.amount,
    required this.dayOfMonth,
    required this.startMonth,
    this.lastGenerated,
    this.isActive = true,
    this.autoGoalId,
    this.autoAmount,
    this.notes,
    required this.createdAt,
  });

  final int? id;
  final int userId;
  final String source;
  final double amount;

  /// Tanggal dalam bulan (1-31). Bulan pendek memakai tanggal terakhir.
  final int dayOfMonth;

  /// Bulan pertama, format "yyyy-MM".
  final String startMonth;

  /// Bulan terakhir pemasukannya dibuat, format "yyyy-MM".
  final String? lastGenerated;
  final bool isActive;

  /// Bila diisi, tiap pemasukan otomatis menyetor [autoAmount] ke target ini.
  final int? autoGoalId;
  final double? autoAmount;
  final String? notes;
  final DateTime createdAt;

  bool get hasAutoAllocation => autoGoalId != null && (autoAmount ?? 0) > 0;

  factory RecurringIncomeModel.fromMap(Map<String, Object?> map) {
    return RecurringIncomeModel(
      id: map[RecurringIncomeCols.id] as int?,
      userId: map[RecurringIncomeCols.userId] as int? ?? 0,
      source: map[RecurringIncomeCols.source] as String? ?? '',
      amount: (map[RecurringIncomeCols.amount] as num?)?.toDouble() ?? 0,
      dayOfMonth: map[RecurringIncomeCols.dayOfMonth] as int? ?? 1,
      startMonth: map[RecurringIncomeCols.startMonth] as String? ?? '',
      lastGenerated: map[RecurringIncomeCols.lastGenerated] as String?,
      isActive: (map[RecurringIncomeCols.isActive] as int? ?? 1) == 1,
      autoGoalId: map[RecurringIncomeCols.autoGoalId] as int?,
      autoAmount: (map[RecurringIncomeCols.autoAmount] as num?)?.toDouble(),
      notes: map[RecurringIncomeCols.notes] as String?,
      createdAt: DbDateUtils.parseOrNow(map[RecurringIncomeCols.createdAt]),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) RecurringIncomeCols.id: id,
      RecurringIncomeCols.userId: userId,
      RecurringIncomeCols.source: source,
      RecurringIncomeCols.amount: amount,
      RecurringIncomeCols.dayOfMonth: dayOfMonth,
      RecurringIncomeCols.startMonth: startMonth,
      RecurringIncomeCols.lastGenerated: lastGenerated,
      RecurringIncomeCols.isActive: isActive ? 1 : 0,
      RecurringIncomeCols.autoGoalId: autoGoalId,
      RecurringIncomeCols.autoAmount: autoAmount,
      RecurringIncomeCols.notes: notes,
      RecurringIncomeCols.createdAt: DbDateUtils.dateTimeToDb(createdAt),
    };
  }

  RecurringIncomeModel copyWith({int? id}) {
    return RecurringIncomeModel(
      id: id ?? this.id,
      userId: userId,
      source: source,
      amount: amount,
      dayOfMonth: dayOfMonth,
      startMonth: startMonth,
      lastGenerated: lastGenerated,
      isActive: isActive,
      autoGoalId: autoGoalId,
      autoAmount: autoAmount,
      notes: notes,
      createdAt: createdAt,
    );
  }
}
