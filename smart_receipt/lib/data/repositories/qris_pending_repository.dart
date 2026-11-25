import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../database/app_database.dart';
import '../models/qris_pending_model.dart';

/// Akses data QRIS yang menunggu struk.
class QrisPendingRepository {
  QrisPendingRepository({AppDatabase? database})
      : _appDatabase = database ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  Future<Database> get _db => _appDatabase.database;

  /// Yang terbaru lebih dulu.
  Future<List<QrisPendingModel>> getAll(int userId) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      DbTables.qrisPending,
      where: '${QrisPendingCols.userId} = ?',
      whereArgs: <Object?>[userId],
      orderBy: '${QrisPendingCols.scannedAt} DESC, ${QrisPendingCols.id} DESC',
    );
    return rows.map(QrisPendingModel.fromMap).toList();
  }

  Future<QrisPendingModel?> getById(int id) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      DbTables.qrisPending,
      where: '${QrisPendingCols.id} = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return rows.isEmpty ? null : QrisPendingModel.fromMap(rows.first);
  }

  Future<int> count(int userId) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM ${DbTables.qrisPending} '
      'WHERE ${QrisPendingCols.userId} = ?',
      <Object?>[userId],
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  Future<QrisPendingModel> insert(QrisPendingModel pending) async {
    final Database db = await _db;
    final int id = await db.insert(DbTables.qrisPending, pending.toMap());
    return pending.copyWith(id: id);
  }

  Future<void> delete(int id) async {
    final Database db = await _db;
    await db.delete(
      DbTables.qrisPending,
      where: '${QrisPendingCols.id} = ?',
      whereArgs: <Object?>[id],
    );
  }
}
