import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../core/utils/db_date_utils.dart';
import '../database/app_database.dart';
import '../models/income_model.dart';

/// Akses data pemasukan dan pemasukan berulang.
class IncomeRepository {
  IncomeRepository({AppDatabase? database})
      : _appDatabase = database ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  Future<Database> get _db => _appDatabase.database;

  // ------------------------------------------------------------ pemasukan

  /// Semua pemasukan pengguna, terbaru lebih dulu.
  Future<List<IncomeModel>> getAll(int userId, {int limit = 1000}) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      DbTables.incomes,
      where: '${IncomeCols.userId} = ?',
      whereArgs: <Object?>[userId],
      orderBy: '${IncomeCols.incomeDate} DESC, ${IncomeCols.id} DESC',
      limit: limit,
    );
    return rows.map(IncomeModel.fromMap).toList();
  }

  /// Pemasukan pada rentang [start, endExclusive), terbaru lebih dulu.
  Future<List<IncomeModel>> getBetween(
    int userId,
    DateTime start,
    DateTime endExclusive,
  ) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      DbTables.incomes,
      where: '${IncomeCols.userId} = ? '
          'AND ${IncomeCols.incomeDate} >= ? AND ${IncomeCols.incomeDate} < ?',
      whereArgs: <Object?>[
        userId,
        DbDateUtils.dateToDb(start),
        DbDateUtils.dateToDb(endExclusive),
      ],
      orderBy: '${IncomeCols.incomeDate} DESC, ${IncomeCols.id} DESC',
    );
    return rows.map(IncomeModel.fromMap).toList();
  }

  Future<double> getTotalBetween(
    int userId,
    DateTime start,
    DateTime endExclusive,
  ) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COALESCE(SUM(${IncomeCols.amount}), 0) AS total '
      'FROM ${DbTables.incomes} '
      'WHERE ${IncomeCols.userId} = ? '
      'AND ${IncomeCols.incomeDate} >= ? AND ${IncomeCols.incomeDate} < ?',
      <Object?>[
        userId,
        DbDateUtils.dateToDb(start),
        DbDateUtils.dateToDb(endExclusive),
      ],
    );
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<IncomeModel> insert(IncomeModel income) async {
    final Database db = await _db;
    final int id = await db.insert(DbTables.incomes, income.toMap());
    return income.copyWith(id: id);
  }

  Future<void> update(IncomeModel income) async {
    final int? id = income.id;
    if (id == null) return;
    final Database db = await _db;
    await db.update(
      DbTables.incomes,
      income.toMap(),
      where: '${IncomeCols.id} = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> delete(int id) async {
    final Database db = await _db;
    await db.delete(
      DbTables.incomes,
      where: '${IncomeCols.id} = ?',
      whereArgs: <Object?>[id],
    );
  }

  // ----------------------------------------------------------- berulang

  Future<List<RecurringIncomeModel>> getRecurring(int userId) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      DbTables.recurringIncomes,
      where: '${RecurringIncomeCols.userId} = ?',
      whereArgs: <Object?>[userId],
      orderBy: '${RecurringIncomeCols.dayOfMonth} ASC',
    );
    return rows.map(RecurringIncomeModel.fromMap).toList();
  }

  Future<RecurringIncomeModel> insertRecurring(
      RecurringIncomeModel model) async {
    final Database db = await _db;
    final int id = await db.insert(DbTables.recurringIncomes, model.toMap());
    return model.copyWith(id: id);
  }

  Future<void> setRecurringActive(int id, bool isActive) async {
    final Database db = await _db;
    await db.update(
      DbTables.recurringIncomes,
      <String, Object?>{RecurringIncomeCols.isActive: isActive ? 1 : 0},
      where: '${RecurringIncomeCols.id} = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> setRecurringLastGenerated(int id, String monthKey) async {
    final Database db = await _db;
    await db.update(
      DbTables.recurringIncomes,
      <String, Object?>{RecurringIncomeCols.lastGenerated: monthKey},
      where: '${RecurringIncomeCols.id} = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> deleteRecurring(int id) async {
    final Database db = await _db;
    await db.delete(
      DbTables.recurringIncomes,
      where: '${RecurringIncomeCols.id} = ?',
      whereArgs: <Object?>[id],
    );
  }
}
