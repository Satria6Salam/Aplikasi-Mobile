import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../core/utils/db_date_utils.dart';
import '../database/app_database.dart';
import '../models/savings_models.dart';

/// Akses data target tabungan dan setorannya.
class SavingsRepository {
  SavingsRepository({AppDatabase? database})
      : _appDatabase = database ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  Future<Database> get _db => _appDatabase.database;

  static const String _goalSelect = '''
SELECT g.*,
  COALESCE((SELECT SUM(d.${DepositCols.amount})
            FROM ${DbTables.savingsDeposits} d
            WHERE d.${DepositCols.goalId} = g.${GoalCols.id}), 0) AS saved_amount
FROM ${DbTables.savingsGoals} g
''';

  /// Target pengguna beserta jumlah yang sudah ditabung. Tenggat terdekat
  /// lebih dulu; target tanpa tenggat di bagian akhir.
  Future<List<SavingsGoalModel>> getGoals(int userId) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '$_goalSelect WHERE g.${GoalCols.userId} = ? '
      'ORDER BY CASE WHEN g.${GoalCols.deadline} IS NULL THEN 1 ELSE 0 END, '
      'g.${GoalCols.deadline} ASC, g.${GoalCols.id} ASC',
      <Object?>[userId],
    );
    return rows.map(SavingsGoalModel.fromMap).toList();
  }

  Future<SavingsGoalModel?> getGoal(int id) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '$_goalSelect WHERE g.${GoalCols.id} = ?',
      <Object?>[id],
    );
    return rows.isEmpty ? null : SavingsGoalModel.fromMap(rows.first);
  }

  Future<SavingsGoalModel> insertGoal(SavingsGoalModel goal) async {
    final Database db = await _db;
    final int id = await db.insert(DbTables.savingsGoals, goal.toMap());
    return goal.copyWith(id: id);
  }

  Future<void> updateGoal(SavingsGoalModel goal) async {
    final int? id = goal.id;
    if (id == null) return;
    final Database db = await _db;
    await db.update(
      DbTables.savingsGoals,
      goal.toMap(),
      where: '${GoalCols.id} = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Menghapus target beserta seluruh setorannya.
  Future<void> deleteGoal(int id) async {
    final Database db = await _db;
    await db.delete(
      DbTables.savingsGoals,
      where: '${GoalCols.id} = ?',
      whereArgs: <Object?>[id],
    );
  }

  // -------------------------------------------------------------- setoran

  /// Riwayat setoran/penarikan sebuah target, terbaru lebih dulu.
  Future<List<SavingsDepositModel>> getDeposits(int goalId) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      DbTables.savingsDeposits,
      where: '${DepositCols.goalId} = ?',
      whereArgs: <Object?>[goalId],
      orderBy: '${DepositCols.depositDate} DESC, ${DepositCols.id} DESC',
    );
    return rows.map(SavingsDepositModel.fromMap).toList();
  }

  Future<void> insertDeposit(SavingsDepositModel deposit) =>
      insertDeposits(<SavingsDepositModel>[deposit]);

  /// Menyimpan beberapa setoran sekaligus; semuanya berhasil atau tidak sama sekali.
  Future<void> insertDeposits(List<SavingsDepositModel> deposits) async {
    if (deposits.isEmpty) return;
    final Database db = await _db;
    await db.transaction((Transaction txn) async {
      for (final SavingsDepositModel d in deposits) {
        await txn.insert(DbTables.savingsDeposits, d.toMap());
      }
    });
  }

  Future<void> deleteDeposit(int id) async {
    final Database db = await _db;
    await db.delete(
      DbTables.savingsDeposits,
      where: '${DepositCols.id} = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Setoran dikurangi penarikan pada rentang [start, endExclusive).
  Future<double> getNetDepositsBetween(
    int userId,
    DateTime start,
    DateTime endExclusive,
  ) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COALESCE(SUM(${DepositCols.amount}), 0) AS total '
      'FROM ${DbTables.savingsDeposits} '
      'WHERE ${DepositCols.userId} = ? '
      'AND ${DepositCols.depositDate} >= ? AND ${DepositCols.depositDate} < ?',
      <Object?>[
        userId,
        DbDateUtils.dateToDb(start),
        DbDateUtils.dateToDb(endExclusive),
      ],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }
}
