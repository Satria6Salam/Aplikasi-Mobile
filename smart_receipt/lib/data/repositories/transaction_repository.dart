import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../core/utils/db_date_utils.dart';
import '../database/app_database.dart';
import '../models/category_summary_model.dart';
import '../models/ml_classification_model.dart';
import '../models/ocr_result_model.dart';
import '../models/purchase_record_model.dart';
import '../models/transaction_filter.dart';
import '../models/parsed_receipt_model.dart';
import '../models/tfidf_feature_model.dart';
import '../models/transaction_item_model.dart';
import '../models/transaction_model.dart';
import 'repository_exception.dart';

/// Akses data transaksi final serta ringkasan untuk Dasbor Keuangan (UC-04).
class TransactionRepository {
  TransactionRepository({AppDatabase? database})
      : _appDatabase = database ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  Future<Database> get _db => _appDatabase.database;

  static const String _joinedSelect = '''
SELECT t.*, c.${CategoryCols.name} AS ${CategoryCols.name}
FROM ${DbTables.transactions} t
INNER JOIN ${DbTables.categories} c ON c.${CategoryCols.id} = t.${TransCols.categoryId}
''';

  /// Batas awal (inklusif) dan akhir (eksklusif) sebuah rentang dalam format yyyy-MM-dd.
  (String, String) _range(DateTime start, DateTime endExclusive) {
    return (
      DbDateUtils.dateToDb(start),
      DbDateUtils.dateToDb(endExclusive),
    );
  }

  /// Menyimpan seluruh hasil pemindaian (OCR, parsing, klasifikasi, fitur TF-IDF)
  /// beserta transaksi final dalam SATU transaksi database.
  /// Dipanggil hanya saat pengguna menekan "Simpan"; jika dibatalkan, tidak ada data tersimpan.
  Future<TransactionModel> saveScanTransaction({
    required OcrResultModel ocr,
    required ParsedReceiptModel parsed,
    required MlClassificationModel classification,
    required List<TfidfFeatureModel> features,
    required TransactionModel transaction,
    List<TransactionItemModel> items = const <TransactionItemModel>[],
  }) async {
    final Database db = await _db;
    return db.transaction((Transaction txn) async {
      final int ocrId = await txn.insert(DbTables.ocrResults, ocr.toMap());

      final int parsedId = await txn.insert(
        DbTables.parsedReceipts,
        parsed.copyWith(ocrId: ocrId).toMap(),
      );

      final int classificationId = await txn.insert(
        DbTables.mlClassifications,
        classification.copyWith(parsedId: parsedId).toMap(),
      );

      for (final TfidfFeatureModel feature in features) {
        await txn.insert(
          DbTables.tfidfFeatures,
          feature.copyWith(classificationId: classificationId).toMap(),
        );
      }

      final TransactionModel complete = transaction.copyWith(
        ocrId: ocrId,
        parsedId: parsedId,
        classificationId: classificationId,
      );
      final int transactionId = await txn.insert(
        DbTables.transactions,
        complete.toMap(),
      );
      for (final TransactionItemModel item in items) {
        await txn.insert(
          DbTables.transactionItems,
          item.copyWith(transactionId: transactionId).toMap(),
        );
      }
      return complete.copyWith(id: transactionId);
    });
  }

  /// Melengkapi transaksi yang sudah ada (mis. hasil Scan QRIS) dengan hasil
  /// scan struknya: jejak OCR, parsing, klasifikasi, serta rincian barang,
  /// dalam SATU transaksi database. Nama toko, tanggal, total, dan catatan
  /// transaksi lama tidak diubah; kategori utama mengikuti barang terbesar.
  /// Cabang, alamat, dan lokasi hanya diisi bila masih kosong, sehingga titik
  /// yang diambil saat memindai QRIS di toko tetap dipakai.
  Future<void> completeWithScan({
    required int transactionId,
    required OcrResultModel ocr,
    required ParsedReceiptModel parsed,
    required MlClassificationModel classification,
    required List<TfidfFeatureModel> features,
    required List<TransactionItemModel> items,
    required int categoryId,
    String? storeBranch,
    String? storeAddress,
  }) async {
    final Database db = await _db;
    await db.transaction((Transaction txn) async {
      final int ocrId = await txn.insert(DbTables.ocrResults, ocr.toMap());
      final int parsedId = await txn.insert(
        DbTables.parsedReceipts,
        parsed.copyWith(ocrId: ocrId).toMap(),
      );
      final int classificationId = await txn.insert(
        DbTables.mlClassifications,
        classification.copyWith(parsedId: parsedId).toMap(),
      );
      for (final TfidfFeatureModel feature in features) {
        await txn.insert(
          DbTables.tfidfFeatures,
          feature.copyWith(classificationId: classificationId).toMap(),
        );
      }
      for (final TransactionItemModel item in items) {
        await txn.insert(
          DbTables.transactionItems,
          item.copyWith(transactionId: transactionId).toMap(),
        );
      }
      await txn.rawUpdate(
        'UPDATE ${DbTables.transactions} SET '
        '${TransCols.ocrId} = ?, '
        '${TransCols.parsedId} = ?, '
        '${TransCols.classificationId} = ?, '
        '${TransCols.categoryId} = ?, '
        '${TransCols.storeBranch} = COALESCE(${TransCols.storeBranch}, ?), '
        '${TransCols.storeAddress} = COALESCE(${TransCols.storeAddress}, ?), '
        '${TransCols.updatedAt} = ? '
        'WHERE ${TransCols.id} = ?',
        <Object?>[
          ocrId,
          parsedId,
          classificationId,
          categoryId,
          storeBranch,
          storeAddress,
          DbDateUtils.dateTimeToDb(DateTime.now()),
          transactionId,
        ],
      );
    });
  }

  /// Kategori yang terakhir dipakai untuk toko ber-NMID [merchantId]; null
  /// bila belum pernah. Dipakai agar koreksi kategori pengguna diingat.
  Future<int?> findCategoryByMerchantId(int userId, String merchantId) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      DbTables.transactions,
      columns: <String>[TransCols.categoryId],
      where: '${TransCols.userId} = ? AND ${TransCols.merchantId} = ?',
      whereArgs: <Object?>[userId, merchantId],
      orderBy: '${TransCols.transactionDate} DESC, ${TransCols.id} DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first[TransCols.categoryId] as int?;
  }

  /// Menyimpan transaksi tanpa jejak OCR/AI (misalnya input manual).
  Future<TransactionModel> insert(TransactionModel transaction) async {
    final Database db = await _db;
    final int id = await db.insert(DbTables.transactions, transaction.toMap());
    return transaction.copyWith(id: id);
  }

  Future<TransactionModel?> getById(int id) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '$_joinedSelect WHERE t.${TransCols.id} = ? LIMIT 1',
      <Object?>[id],
    );
    return rows.isEmpty ? null : TransactionModel.fromMap(rows.first);
  }

  /// Riwayat transaksi terbaru lebih dulu.
  Future<List<TransactionModel>> getByUser(
    int userId, {
    int? limit,
    int? offset,
  }) async {
    final Database db = await _db;
    final StringBuffer sql = StringBuffer(_joinedSelect)
      ..write('WHERE t.${TransCols.userId} = ? ')
      ..write(
        'ORDER BY t.${TransCols.transactionDate} DESC, t.${TransCols.id} DESC',
      );
    final List<Object?> args = <Object?>[userId];
    if (limit != null) {
      sql.write(' LIMIT ?');
      args.add(limit);
      if (offset != null) {
        sql.write(' OFFSET ?');
        args.add(offset);
      }
    }
    final List<Map<String, Object?>> rows =
        await db.rawQuery(sql.toString(), args);
    return rows.map(TransactionModel.fromMap).toList();
  }

  // ------------------------------------------------------------- pencarian

  static const String _escape = r" ESCAPE '\'";

  /// Pola LIKE untuk satu kata; karakter khusus (% _ \) diloloskan.
  static String _like(String token) {
    final String escaped = token
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    return '%$escaped%';
  }

  static String _placeholders(int count) =>
      List<String>.filled(count, '?').join(',');

  /// Pencarian transaksi lintas periode. Setiap kata kunci harus cocok di
  /// nama toko, cabang, alamat, catatan, atau nama barang; filter tanggal,
  /// total struk, dan kategori (utama atau salah satu barang) bersifat DAN.
  Future<List<TransactionModel>> searchTransactions(
    int userId,
    TransactionFilter filter, {
    int limit = 300,
  }) async {
    final Database db = await _db;
    final List<String> where = <String>['t.${TransCols.userId} = ?'];
    final List<Object?> args = <Object?>[userId];

    for (final String token in filter.tokens) {
      final String like = _like(token);
      where.add(
        '(t.${TransCols.merchantName} LIKE ?$_escape '
        'OR t.${TransCols.notes} LIKE ?$_escape '
        'OR t.${TransCols.storeBranch} LIKE ?$_escape '
        'OR t.${TransCols.storeAddress} LIKE ?$_escape '
        'OR EXISTS (SELECT 1 FROM ${DbTables.transactionItems} i '
        'WHERE i.${ItemCols.transactionId} = t.${TransCols.id} '
        'AND i.${ItemCols.name} LIKE ?$_escape))',
      );
      args.addAll(<Object?>[like, like, like, like, like]);
    }
    final DateTime? from = filter.from;
    if (from != null) {
      where.add('t.${TransCols.transactionDate} >= ?');
      args.add(DbDateUtils.dateToDb(from));
    }
    final DateTime? to = filter.to;
    if (to != null) {
      where.add('t.${TransCols.transactionDate} <= ?');
      args.add(DbDateUtils.dateToDb(to));
    }
    final double? minTotal = filter.minTotal;
    if (minTotal != null) {
      where.add('t.${TransCols.totalAmount} >= ?');
      args.add(minTotal);
    }
    final double? maxTotal = filter.maxTotal;
    if (maxTotal != null) {
      where.add('t.${TransCols.totalAmount} <= ?');
      args.add(maxTotal);
    }
    if (filter.hasCategories) {
      final List<int> ids = filter.categoryIds.toList();
      final String marks = _placeholders(ids.length);
      where.add(
        '(t.${TransCols.categoryId} IN ($marks) '
        'OR EXISTS (SELECT 1 FROM ${DbTables.transactionItems} i '
        'WHERE i.${ItemCols.transactionId} = t.${TransCols.id} '
        'AND i.${ItemCols.categoryId} IN ($marks)))',
      );
      args
        ..addAll(ids)
        ..addAll(ids);
    }

    final String order = switch (filter.sort) {
      SearchSort.newest =>
        't.${TransCols.transactionDate} DESC, t.${TransCols.id} DESC',
      SearchSort.oldest =>
        't.${TransCols.transactionDate} ASC, t.${TransCols.id} ASC',
      SearchSort.highest =>
        't.${TransCols.totalAmount} DESC, t.${TransCols.id} DESC',
      SearchSort.lowest =>
        't.${TransCols.totalAmount} ASC, t.${TransCols.id} DESC',
    };
    args.add(limit);

    final List<Map<String, Object?>> rows = await db.rawQuery(
      '$_joinedSelect WHERE ${where.join(' AND ')} ORDER BY $order LIMIT ?',
      args,
    );
    return rows.map(TransactionModel.fromMap).toList();
  }

  /// Barang yang pernah dibeli beserta toko dan tanggalnya, terbaru dulu.
  /// Kata kunci dicocokkan dengan nama barang atau nama toko; filter tanggal
  /// dan kategori berlaku pada barangnya. Tanpa kata kunci, semua barang
  /// dikembalikan (dipakai untuk perbandingan harga).
  Future<List<PurchaseRecord>> searchPurchases(
    int userId,
    TransactionFilter filter, {
    int limit = 500,
  }) async {
    final Database db = await _db;
    final List<String> where = <String>['t.${TransCols.userId} = ?'];
    final List<Object?> args = <Object?>[userId];

    for (final String token in filter.tokens) {
      final String like = _like(token);
      where.add(
        '(i.${ItemCols.name} LIKE ?$_escape '
        'OR t.${TransCols.merchantName} LIKE ?$_escape)',
      );
      args.addAll(<Object?>[like, like]);
    }
    final DateTime? from = filter.from;
    if (from != null) {
      where.add('t.${TransCols.transactionDate} >= ?');
      args.add(DbDateUtils.dateToDb(from));
    }
    final DateTime? to = filter.to;
    if (to != null) {
      where.add('t.${TransCols.transactionDate} <= ?');
      args.add(DbDateUtils.dateToDb(to));
    }
    if (filter.hasCategories) {
      final List<int> ids = filter.categoryIds.toList();
      where.add('i.${ItemCols.categoryId} IN (${_placeholders(ids.length)})');
      args.addAll(ids);
    }
    args.add(limit);

    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT i.*, '
      'c.${CategoryCols.name} AS ${CategoryCols.name}, '
      't.${TransCols.merchantName} AS ${TransCols.merchantName}, '
      't.${TransCols.storeBranch} AS ${TransCols.storeBranch}, '
      't.${TransCols.transactionDate} AS ${TransCols.transactionDate} '
      'FROM ${DbTables.transactionItems} i '
      'INNER JOIN ${DbTables.transactions} t '
      'ON t.${TransCols.id} = i.${ItemCols.transactionId} '
      'INNER JOIN ${DbTables.categories} c '
      'ON c.${CategoryCols.id} = i.${ItemCols.categoryId} '
      'WHERE ${where.join(' AND ')} '
      'ORDER BY t.${TransCols.transactionDate} DESC, i.${ItemCols.id} DESC '
      'LIMIT ?',
      args,
    );
    return rows.map(PurchaseRecord.fromMap).toList();
  }

  /// Transaksi pengguna pada tanggal yang sama dengan total yang sama
  /// (selisih maksimal [tolerance] rupiah); bahan deteksi struk ganda.
  Future<List<TransactionModel>> findSameDayAmount(
    int userId,
    DateTime date,
    double total, {
    double tolerance = 1,
  }) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '$_joinedSelect '
      'WHERE t.${TransCols.userId} = ? '
      'AND t.${TransCols.transactionDate} = ? '
      'AND ABS(t.${TransCols.totalAmount} - ?) <= ? '
      'ORDER BY t.${TransCols.id} DESC',
      <Object?>[userId, DbDateUtils.dateToDb(date), total, tolerance],
    );
    return rows.map(TransactionModel.fromMap).toList();
  }

  /// Transaksi yang memiliki koordinat toko (untuk Peta Toko), terbaru dulu.
  Future<List<TransactionModel>> getWithLocation(int userId) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '$_joinedSelect '
      'WHERE t.${TransCols.userId} = ? '
      'AND t.${TransCols.latitude} IS NOT NULL '
      'AND t.${TransCols.longitude} IS NOT NULL '
      'ORDER BY t.${TransCols.transactionDate} DESC, t.${TransCols.id} DESC',
      <Object?>[userId],
    );
    return rows.map(TransactionModel.fromMap).toList();
  }

  /// Transaksi pada rentang [start, endExclusive), terbaru lebih dulu.
  Future<List<TransactionModel>> getBetween(
    int userId,
    DateTime start,
    DateTime endExclusive,
  ) async {
    final Database db = await _db;
    final (String from, String to) = _range(start, endExclusive);
    final List<Map<String, Object?>> rows = await db.rawQuery(
      '$_joinedSelect '
      'WHERE t.${TransCols.userId} = ? '
      'AND t.${TransCols.transactionDate} >= ? '
      'AND t.${TransCols.transactionDate} < ? '
      'ORDER BY t.${TransCols.transactionDate} DESC, t.${TransCols.id} DESC',
      <Object?>[userId, from, to],
    );
    return rows.map(TransactionModel.fromMap).toList();
  }

  Future<List<TransactionModel>> getByMonth(
    int userId,
    int year,
    int month,
  ) {
    return getBetween(userId, DateTime(year, month), DateTime(year, month + 1));
  }

  Future<bool> update(TransactionModel transaction) async {
    final int? id = transaction.id;
    if (id == null) {
      throw const RepositoryException('ID transaksi tidak ditemukan');
    }
    final Database db = await _db;
    final Map<String, Object?> values = Map<String, Object?>.of(
      transaction.copyWith(updatedAt: DateTime.now()).toMap(),
    )..remove(TransCols.id);
    final int count = await db.update(
      DbTables.transactions,
      values,
      where: '${TransCols.id} = ?',
      whereArgs: <Object?>[id],
    );
    return count > 0;
  }

  /// Menghapus transaksi beserta jejak OCR/parsing/klasifikasi/TF-IDF miliknya.
  Future<bool> delete(int id) async {
    final Database db = await _db;
    return db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> rows = await txn.query(
        DbTables.transactions,
        columns: <String>[TransCols.ocrId],
        where: '${TransCols.id} = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (rows.isEmpty) return false;
      final int? ocrId = rows.first[TransCols.ocrId] as int?;

      await txn.delete(
        DbTables.transactions,
        where: '${TransCols.id} = ?',
        whereArgs: <Object?>[id],
      );
      if (ocrId != null) {
        // Cascade ke parsed_receipts, ml_classifications, dan tfidf_features.
        await txn.delete(
          DbTables.ocrResults,
          where: '${OcrCols.id} = ?',
          whereArgs: <Object?>[ocrId],
        );
      }
      return true;
    });
  }

  /// Total pengeluaran pada rentang [start, endExclusive).
  Future<double> getTotalBetween(
    int userId,
    DateTime start,
    DateTime endExclusive,
  ) async {
    final Database db = await _db;
    final (String from, String to) = _range(start, endExclusive);
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COALESCE(SUM(${TransCols.totalAmount}), 0) AS total '
      'FROM ${DbTables.transactions} '
      'WHERE ${TransCols.userId} = ? '
      'AND ${TransCols.transactionDate} >= ? '
      'AND ${TransCols.transactionDate} < ?',
      <Object?>[userId, from, to],
    );
    if (rows.isEmpty) return 0.0;
    return (rows.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Total pengeluaran pada bulan tertentu.
  Future<double> getMonthlyTotal(int userId, int year, int month) {
    return getTotalBetween(
        userId, DateTime(year, month), DateTime(year, month + 1));
  }

  /// Total pengeluaran per bulan (indeks 0 = Januari) pada satu tahun.
  Future<List<double>> getMonthlyTotals(int userId, int year) async {
    final Database db = await _db;
    final (String from, String to) = _range(DateTime(year), DateTime(year + 1));
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT substr(${TransCols.transactionDate}, 6, 2) AS month_key, '
      'SUM(${TransCols.totalAmount}) AS total '
      'FROM ${DbTables.transactions} '
      'WHERE ${TransCols.userId} = ? '
      'AND ${TransCols.transactionDate} >= ? '
      'AND ${TransCols.transactionDate} < ? '
      'GROUP BY month_key',
      <Object?>[userId, from, to],
    );
    final List<double> result = List<double>.filled(12, 0);
    for (final Map<String, Object?> row in rows) {
      final int? month = int.tryParse(row['month_key'] as String? ?? '');
      if (month != null && month >= 1 && month <= 12) {
        result[month - 1] = (row['total'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return result;
  }

  /// Total pengeluaran per tahun (urut dari tahun terlama).
  Future<Map<int, double>> getYearlyTotals(int userId) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT substr(${TransCols.transactionDate}, 1, 4) AS year_key, '
      'SUM(${TransCols.totalAmount}) AS total '
      'FROM ${DbTables.transactions} '
      'WHERE ${TransCols.userId} = ? '
      'GROUP BY year_key ORDER BY year_key ASC',
      <Object?>[userId],
    );
    final Map<int, double> result = <int, double>{};
    for (final Map<String, Object?> row in rows) {
      final int? year = int.tryParse(row['year_key'] as String? ?? '');
      if (year != null) {
        result[year] = (row['total'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return result;
  }

  /// Total pengeluaran per kategori pada rentang waktu (terbesar lebih dulu).
  /// Dihitung dari rincian barang; transaksi lama tanpa rincian memakai
  /// kategori transaksinya.
  Future<List<CategorySummaryModel>> getCategorySummaryBetween(
    int userId,
    DateTime start,
    DateTime endExclusive,
  ) async {
    final Database db = await _db;
    final (String from, String to) = _range(start, endExclusive);
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT c.${CategoryCols.id} AS category_id, '
      'c.${CategoryCols.name} AS category_name, '
      'SUM(x.amount) AS total_amount, '
      'COUNT(DISTINCT x.tid) AS transaction_count '
      'FROM ('
      'SELECT i.${ItemCols.categoryId} AS cid, i.${ItemCols.totalPrice} AS amount, '
      'i.${ItemCols.transactionId} AS tid '
      'FROM ${DbTables.transactionItems} i '
      'INNER JOIN ${DbTables.transactions} t ON t.${TransCols.id} = i.${ItemCols.transactionId} '
      'WHERE t.${TransCols.userId} = ? '
      'AND t.${TransCols.transactionDate} >= ? '
      'AND t.${TransCols.transactionDate} < ? '
      'UNION ALL '
      'SELECT t.${TransCols.categoryId} AS cid, t.${TransCols.totalAmount} AS amount, '
      't.${TransCols.id} AS tid '
      'FROM ${DbTables.transactions} t '
      'WHERE t.${TransCols.userId} = ? '
      'AND t.${TransCols.transactionDate} >= ? '
      'AND t.${TransCols.transactionDate} < ? '
      'AND NOT EXISTS (SELECT 1 FROM ${DbTables.transactionItems} i2 '
      'WHERE i2.${ItemCols.transactionId} = t.${TransCols.id})'
      ') x '
      'INNER JOIN ${DbTables.categories} c ON c.${CategoryCols.id} = x.cid '
      'GROUP BY c.${CategoryCols.id}, c.${CategoryCols.name} '
      'ORDER BY total_amount DESC',
      <Object?>[userId, from, to, userId, from, to],
    );
    return rows.map(CategorySummaryModel.fromMap).toList();
  }

  /// Total pengeluaran per kategori pada bulan tertentu.
  Future<List<CategorySummaryModel>> getCategorySummary(
    int userId,
    int year,
    int month,
  ) {
    return getCategorySummaryBetween(
      userId,
      DateTime(year, month),
      DateTime(year, month + 1),
    );
  }

  /// Jumlah pengeluaran per kategori pada tiap transaksi dalam rentang waktu:
  /// transaksi -> (kategori -> jumlah). Dipakai untuk menyaring riwayat berdasarkan kategori.
  /// Transaksi lama tanpa rincian barang memakai kategori transaksinya.
  Future<Map<int, Map<int, double>>> getCategoryAmountsByTransaction(
    int userId,
    DateTime start,
    DateTime endExclusive,
  ) async {
    final Database db = await _db;
    final (String from, String to) = _range(start, endExclusive);
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT x.tid AS tid, x.cid AS cid, SUM(x.amount) AS amount FROM ('
      'SELECT i.${ItemCols.transactionId} AS tid, i.${ItemCols.categoryId} AS cid, '
      'i.${ItemCols.totalPrice} AS amount '
      'FROM ${DbTables.transactionItems} i '
      'INNER JOIN ${DbTables.transactions} t ON t.${TransCols.id} = i.${ItemCols.transactionId} '
      'WHERE t.${TransCols.userId} = ? '
      'AND t.${TransCols.transactionDate} >= ? '
      'AND t.${TransCols.transactionDate} < ? '
      'UNION ALL '
      'SELECT t.${TransCols.id} AS tid, t.${TransCols.categoryId} AS cid, '
      't.${TransCols.totalAmount} AS amount '
      'FROM ${DbTables.transactions} t '
      'WHERE t.${TransCols.userId} = ? '
      'AND t.${TransCols.transactionDate} >= ? '
      'AND t.${TransCols.transactionDate} < ? '
      'AND NOT EXISTS (SELECT 1 FROM ${DbTables.transactionItems} i2 '
      'WHERE i2.${ItemCols.transactionId} = t.${TransCols.id})'
      ') x GROUP BY x.tid, x.cid',
      <Object?>[userId, from, to, userId, from, to],
    );
    final Map<int, Map<int, double>> result = <int, Map<int, double>>{};
    for (final Map<String, Object?> row in rows) {
      final int? tid = row['tid'] as int?;
      final int? cid = row['cid'] as int?;
      if (tid == null || cid == null) continue;
      final Map<int, double> byCategory =
          result.putIfAbsent(tid, () => <int, double>{});
      byCategory[cid] = (row['amount'] as num?)?.toDouble() ?? 0.0;
    }
    return result;
  }

  /// Rincian barang sebuah transaksi (urut sesuai input).
  Future<List<TransactionItemModel>> getItems(int transactionId) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT i.*, c.${CategoryCols.name} AS ${CategoryCols.name} '
      'FROM ${DbTables.transactionItems} i '
      'INNER JOIN ${DbTables.categories} c ON c.${CategoryCols.id} = i.${ItemCols.categoryId} '
      'WHERE i.${ItemCols.transactionId} = ? '
      'ORDER BY i.${ItemCols.id} ASC',
      <Object?>[transactionId],
    );
    return rows.map(TransactionItemModel.fromMap).toList();
  }

  /// Barang yang dikoreksi atau ditambahkan pengguna; dipakai melatih ulang model AI.
  Future<List<LabeledItem>> getTrainingSamples(int userId,
      {int limit = 2000}) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT i.${ItemCols.name} AS item_name, c.${CategoryCols.name} AS category_name '
      'FROM ${DbTables.transactionItems} i '
      'INNER JOIN ${DbTables.transactions} t ON t.${TransCols.id} = i.${ItemCols.transactionId} '
      'INNER JOIN ${DbTables.categories} c ON c.${CategoryCols.id} = i.${ItemCols.categoryId} '
      'WHERE t.${TransCols.userId} = ? '
      // Hanya koreksi/tambahan pengguna: tebakan AI yang diterima apa adanya tidak
      // perlu dipelajari ulang dan tidak boleh mengunci label lama.
      'AND (i.${ItemCols.aiCategoryId} IS NULL OR i.${ItemCols.aiCategoryId} != i.${ItemCols.categoryId}) '
      'ORDER BY i.${ItemCols.id} DESC LIMIT ?',
      <Object?>[userId, limit],
    );
    return rows
        .map(
          (Map<String, Object?> r) => LabeledItem(
            name: r['item_name'] as String? ?? '',
            categoryName: r['category_name'] as String? ?? '',
          ),
        )
        .where((LabeledItem l) => l.name.trim().isNotEmpty)
        .toList();
  }
}
