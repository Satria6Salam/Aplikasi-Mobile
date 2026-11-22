import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants/db_constants.dart';
import '../../core/utils/db_date_utils.dart';
import '../../services/geocoding_service.dart';
import '../../services/store_address_extractor.dart';
import '../database/app_database.dart';

/// Cache koordinat toko yang pernah dipastikan pengguna, sehingga struk
/// berikutnya dari toko/cabang yang sama tidak perlu memanggil API lagi
/// dan langsung memakai titik yang sudah dikoreksi.
class StoreLocationRepository {
  StoreLocationRepository({AppDatabase? database})
      : _appDatabase = database ?? AppDatabase.instance;

  final AppDatabase _appDatabase;

  Future<Database> get _db => _appDatabase.database;

  /// Kunci pencarian: nama toko + alamat yang dinormalisasi.
  static String keyOf(String merchant, String? address) {
    String norm(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return '${norm(merchant)}|${norm(address ?? '')}';
  }

  Future<StoreLocation?> find(
      int userId, String merchant, String? address) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      DbTables.storeLocations,
      where: '${StoreLocCols.userId} = ? AND ${StoreLocCols.lookupKey} = ?',
      whereArgs: <Object?>[userId, keyOf(merchant, address)],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final Map<String, Object?> r = rows.first;
    return StoreLocation(
      point: LatLng(
        (r[StoreLocCols.latitude] as num).toDouble(),
        (r[StoreLocCols.longitude] as num).toDouble(),
      ),
      displayName: r[StoreLocCols.displayName] as String? ?? '',
      precision: LocationPrecision.values.firstWhere(
        (LocationPrecision p) => p.name == r[StoreLocCols.precision],
        orElse: () => LocationPrecision.street,
      ),
      confidence: (r[StoreLocCols.confidence] as num?)?.toDouble() ?? 0.8,
      source: LocationSource.cache,
    );
  }

  Future<void> save({
    required int userId,
    required String merchant,
    required String? address,
    required StoreLocation location,
  }) async {
    final Database db = await _db;
    await db.insert(
      DbTables.storeLocations,
      <String, Object?>{
        StoreLocCols.userId: userId,
        StoreLocCols.lookupKey: keyOf(merchant, address),
        StoreLocCols.merchantName: merchant,
        StoreLocCols.address: address,
        StoreLocCols.latitude: location.point.latitude,
        StoreLocCols.longitude: location.point.longitude,
        StoreLocCols.displayName: location.displayName,
        StoreLocCols.precision: location.precision.name,
        StoreLocCols.confidence: location.confidence,
        StoreLocCols.source: location.source,
        StoreLocCols.updatedAt: DbDateUtils.dateTimeToDb(DateTime.now()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
