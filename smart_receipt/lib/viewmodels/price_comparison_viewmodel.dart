import 'package:flutter/foundation.dart';

import '../data/models/purchase_record_model.dart';
import '../data/models/transaction_filter.dart';
import '../data/repositories/transaction_repository.dart';
import '../services/price_comparison_service.dart';
import 'auth_viewmodel.dart';
import 'safe_change_notifier.dart';

/// Urutan daftar barang pada layar perbandingan harga.
enum ProductSort { mostBought, biggestSaving, priceUp, priceDown, name }

/// Data layar Bandingkan Harga: seluruh barang yang pernah dibeli,
/// dikelompokkan, dengan pencarian dan pengurutan.
class PriceComparisonViewModel extends ChangeNotifier with SafeChangeNotifier {
  PriceComparisonViewModel({
    required AuthViewModel authViewModel,
    required TransactionRepository transactionRepository,
    PriceComparisonService service = const PriceComparisonService(),
  })  : _auth = authViewModel,
        _transactions = transactionRepository,
        _service = service;

  static const int recordLimit = 20000;

  final AuthViewModel _auth;
  final TransactionRepository _transactions;
  final PriceComparisonService _service;

  List<ProductPrices> _all = <ProductPrices>[];
  bool _loading = false;
  String? _error;
  String _query = '';
  bool _onlyComparable = false;
  ProductSort _sort = ProductSort.mostBought;

  bool get isLoading => _loading;
  String? get errorMessage => _error;
  String get query => _query;
  bool get onlyComparable => _onlyComparable;
  ProductSort get sort => _sort;

  /// Semua barang (tanpa pencarian dan filter).
  List<ProductPrices> get allProducts => _all;

  /// Barang yang dibeli di dua toko atau lebih (bisa dibandingkan).
  int get comparableCount =>
      _all.where((ProductPrices p) => p.isComparable).length;

  /// Barang yang cocok dengan pencarian dan filter, sesuai urutan terpilih.
  List<ProductPrices> get products {
    final List<String> tokens = PriceComparisonService.normalize(_query)
        .split(' ')
        .where((String t) => t.isNotEmpty)
        .toList();
    final List<ProductPrices> list = _all.where((ProductPrices p) {
      if (_onlyComparable && !p.isComparable) return false;
      if (tokens.isEmpty) return true;
      return tokens.every(p.key.contains);
    }).toList();

    double saving(ProductPrices p) => p.potentialSaving ?? -1;
    double change(ProductPrices p) => p.latestChange?.percent ?? 0;
    switch (_sort) {
      case ProductSort.mostBought:
        break; // Urutan bawaan service.
      case ProductSort.biggestSaving:
        list.sort((ProductPrices a, ProductPrices b) =>
            saving(b).compareTo(saving(a)));
      case ProductSort.priceUp:
        list.sort((ProductPrices a, ProductPrices b) =>
            change(b).compareTo(change(a)));
      case ProductSort.priceDown:
        list.sort((ProductPrices a, ProductPrices b) =>
            change(a).compareTo(change(b)));
      case ProductSort.name:
        list.sort((ProductPrices a, ProductPrices b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  Future<void> load() async {
    final int? userId = _auth.currentUser?.id;
    if (userId == null) {
      _all = <ProductPrices>[];
      safeNotify();
      return;
    }
    _loading = true;
    _error = null;
    safeNotify();
    try {
      final List<PurchaseRecord> records = await _transactions.searchPurchases(
          userId, const TransactionFilter(),
          limit: recordLimit);
      _all = _service.compare(records);
    } catch (_) {
      _error = 'Gagal memuat riwayat harga.';
    }
    _loading = false;
    safeNotify();
  }

  void setQuery(String value) {
    _query = value;
    safeNotify();
  }

  void setOnlyComparable(bool value) {
    _onlyComparable = value;
    safeNotify();
  }

  void setSort(ProductSort value) {
    _sort = value;
    safeNotify();
  }

  /// Barang yang paling cocok dengan [name] (mis. dari hasil pencarian);
  /// null bila tidak ada.
  ProductPrices? bestMatch(String name) {
    final String key = PriceComparisonService.normalize(name);
    if (key.isEmpty) return null;
    for (final ProductPrices p in _all) {
      if (p.key == key || PriceComparisonService.sameProduct(p.key, key)) {
        return p;
      }
    }
    final List<String> tokens = key.split(' ');
    for (final ProductPrices p in _all) {
      if (tokens.every(p.key.contains)) return p;
    }
    return null;
  }

  /// Teks ringkasan untuk ditampilkan.
  List<String> insightsOf(ProductPrices p, String Function(double) money) =>
      _service.insights(p, money: money);
}
