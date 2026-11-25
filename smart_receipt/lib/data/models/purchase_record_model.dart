import '../../core/constants/db_constants.dart';
import '../../core/utils/db_date_utils.dart';

/// Satu barang yang pernah dibeli, lengkap dengan toko dan tanggalnya
/// (gabungan `transaction_items` dan `transactions`). Dipakai untuk mencari
/// barang ("kapan terakhir beli telur?") dan membandingkan harga antar toko.
class PurchaseRecord {
  const PurchaseRecord({
    required this.itemId,
    required this.transactionId,
    required this.itemName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.categoryId,
    this.categoryName,
    required this.merchantName,
    this.storeBranch,
    required this.date,
  });

  final int itemId;
  final int transactionId;
  final String itemName;
  final double quantity;

  /// Harga per satuan (dasar perbandingan harga).
  final double unitPrice;
  final double totalPrice;
  final int categoryId;
  final String? categoryName;
  final String merchantName;
  final String? storeBranch;
  final DateTime date;

  factory PurchaseRecord.fromMap(Map<String, Object?> map) {
    return PurchaseRecord(
      itemId: map[ItemCols.id] as int? ?? 0,
      transactionId: map[ItemCols.transactionId] as int? ?? 0,
      itemName: map[ItemCols.name] as String? ?? '',
      quantity: (map[ItemCols.quantity] as num?)?.toDouble() ?? 1.0,
      unitPrice: (map[ItemCols.unitPrice] as num?)?.toDouble() ?? 0.0,
      totalPrice: (map[ItemCols.totalPrice] as num?)?.toDouble() ?? 0.0,
      categoryId: map[ItemCols.categoryId] as int? ?? 0,
      categoryName: map[CategoryCols.name] as String?,
      merchantName: map[TransCols.merchantName] as String? ?? '',
      storeBranch: map[TransCols.storeBranch] as String?,
      date: DbDateUtils.parseOrNow(map[TransCols.transactionDate]),
    );
  }
}
