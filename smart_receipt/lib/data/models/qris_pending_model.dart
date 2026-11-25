import '../../core/constants/db_constants.dart';
import '../../core/utils/db_date_utils.dart';

/// QRIS yang sudah dipindai tetapi nominalnya belum diketahui; menunggu
/// struk untuk dilengkapi. Bukan transaksi, jadi belum dihitung sebagai
/// pengeluaran.
class QrisPendingModel {
  const QrisPendingModel({
    this.id,
    required this.userId,
    required this.merchantName,
    this.city,
    this.merchantId,
    this.mcc,
    this.categoryId,
    this.latitude,
    this.longitude,
    this.locationSource,
    this.notes,
    required this.scannedAt,
  });

  final int? id;
  final int userId;
  final String merchantName;
  final String? city;

  /// NMID dari QRIS.
  final String? merchantId;
  final String? mcc;

  /// Kategori yang dipilih saat memindai (dari MCC atau riwayat toko).
  final int? categoryId;
  final double? latitude;
  final double? longitude;
  final String? locationSource;
  final String? notes;
  final DateTime scannedAt;

  bool get hasLocation => latitude != null && longitude != null;

  factory QrisPendingModel.fromMap(Map<String, Object?> map) {
    return QrisPendingModel(
      id: map[QrisPendingCols.id] as int?,
      userId: map[QrisPendingCols.userId] as int? ?? 0,
      merchantName: map[QrisPendingCols.merchantName] as String? ?? '',
      city: map[QrisPendingCols.city] as String?,
      merchantId: map[QrisPendingCols.merchantId] as String?,
      mcc: map[QrisPendingCols.mcc] as String?,
      categoryId: map[QrisPendingCols.categoryId] as int?,
      latitude: (map[QrisPendingCols.latitude] as num?)?.toDouble(),
      longitude: (map[QrisPendingCols.longitude] as num?)?.toDouble(),
      locationSource: map[QrisPendingCols.locationSource] as String?,
      notes: map[QrisPendingCols.notes] as String?,
      scannedAt: DbDateUtils.parseOrNow(map[QrisPendingCols.scannedAt]),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (id != null) QrisPendingCols.id: id,
      QrisPendingCols.userId: userId,
      QrisPendingCols.merchantName: merchantName,
      QrisPendingCols.city: city,
      QrisPendingCols.merchantId: merchantId,
      QrisPendingCols.mcc: mcc,
      QrisPendingCols.categoryId: categoryId,
      QrisPendingCols.latitude: latitude,
      QrisPendingCols.longitude: longitude,
      QrisPendingCols.locationSource: locationSource,
      QrisPendingCols.notes: notes,
      QrisPendingCols.scannedAt: DbDateUtils.dateTimeToDb(scannedAt),
    };
  }

  QrisPendingModel copyWith({int? id}) => QrisPendingModel(
        id: id ?? this.id,
        userId: userId,
        merchantName: merchantName,
        city: city,
        merchantId: merchantId,
        mcc: mcc,
        categoryId: categoryId,
        latitude: latitude,
        longitude: longitude,
        locationSource: locationSource,
        notes: notes,
        scannedAt: scannedAt,
      );
}
