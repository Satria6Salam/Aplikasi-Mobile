import 'package:flutter_test/flutter_test.dart';
import 'package:smart_receipt/data/database/app_database.dart';
import 'package:smart_receipt/data/database/database_schema.dart';
import 'package:smart_receipt/data/models/transaction_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// AppDatabase tiruan yang memakai SQLite dalam memori dengan skema asli.
class MemoryDatabase extends Fake implements AppDatabase {
  MemoryDatabase(this.db);

  final Database db;

  @override
  Future<Database> get database async => db;
}

/// Membuka basis data dalam memori berisi skema terbaru dan kategori awal.
Future<Database> openMemoryDatabase() async {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (Database db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (Database db, int version) async {
        for (final String statement in DatabaseSchema.createStatements) {
          await db.execute(statement);
        }
        for (final String statement in DatabaseSchema.createIndexes) {
          await db.execute(statement);
        }
        final String now = DateTime(2026, 1, 1).toIso8601String();
        for (final Map<String, String> c in DatabaseSchema.defaultCategories) {
          await db.insert('categories', <String, Object?>{
            'category_name': c['name'],
            'description': c['description'],
            'created_at': now,
          });
        }
      },
    ),
  );
}

Future<void> addUser(Database db, int id) =>
    db.insert('users', <String, Object?>{
      'user_id': id,
      'name': 'Pengguna $id',
      'email': 'u$id@mail.com',
      'password_hash': 'x',
      'created_at': '2026-01-01T00:00:00.000',
      'updated_at': '2026-01-01T00:00:00.000',
    });

/// Menyimpan satu transaksi pengeluaran (tanpa rincian barang).
Future<int> addExpense(
  Database db, {
  required int userId,
  required DateTime date,
  required double total,
  String merchant = 'Toko',
}) {
  final DateTime now = DateTime(2026, 12, 1);
  return db.insert(
    'transactions',
    TransactionModel(
      userId: userId,
      merchantName: merchant,
      transactionDate: date,
      totalAmount: total,
      categoryId: 1,
      createdAt: now,
      updatedAt: now,
    ).toMap(),
  );
}
