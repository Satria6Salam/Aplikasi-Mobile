import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models/category_model.dart';
import '../data/models/purchase_record_model.dart';
import '../data/models/transaction_filter.dart';
import '../data/models/transaction_model.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/transaction_repository.dart';
import 'auth_viewmodel.dart';
import 'safe_change_notifier.dart';

/// Ringkasan pembelian sebuah barang hasil pencarian.
class ItemSearchSummary {
  const ItemSearchSummary({
    required this.latest,
    required this.cheapest,
    required this.count,
    required this.storeCount,
  });

  /// Pembelian terbaru ("kapan terakhir beli, di mana, berapa").
  final PurchaseRecord latest;

  /// Pembelian dengan harga satuan terendah.
  final PurchaseRecord cheapest;
  final int count;
  final int storeCount;
}

/// Pencarian transaksi dan barang lintas periode dengan filter tanggal,
/// total struk, dan kategori. Hasil diperbarui otomatis (dengan jeda singkat
/// saat mengetik agar tidak membebani basis data).
class SearchViewModel extends ChangeNotifier with SafeChangeNotifier {
  SearchViewModel({
    required AuthViewModel authViewModel,
    required TransactionRepository transactionRepository,
    required CategoryRepository categoryRepository,
    Duration debounce = const Duration(milliseconds: 350),
  })  : _auth = authViewModel,
        _transactions = transactionRepository,
        _categoryRepository = categoryRepository,
        _debounce = debounce;

  /// Batas hasil agar daftar tetap ringan.
  static const int resultLimit = 300;
  static const int purchaseLimit = 200;

  final AuthViewModel _auth;
  final TransactionRepository _transactions;
  final CategoryRepository _categoryRepository;
  final Duration _debounce;

  TransactionFilter _filter = const TransactionFilter();
  List<TransactionModel> _results = <TransactionModel>[];
  List<PurchaseRecord> _purchases = <PurchaseRecord>[];
  List<CategoryModel> _categories = <CategoryModel>[];
  bool _loading = false;
  String? _error;
  Timer? _timer;
  int _token = 0;

  TransactionFilter get filter => _filter;
  List<TransactionModel> get results => _results;

  /// Barang yang cocok dengan kata kunci (kosong bila tanpa kata kunci).
  List<PurchaseRecord> get purchases => _purchases;
  List<CategoryModel> get categories => _categories;
  bool get isLoading => _loading;
  String? get errorMessage => _error;

  /// True bila hasil dibatasi [resultLimit]; masih ada yang tidak tampil.
  bool get isTruncated => _results.length >= resultLimit;

  double get totalAmount => _results.fold<double>(
      0, (double s, TransactionModel t) => s + t.totalAmount);

  ItemSearchSummary? get itemSummary {
    if (_purchases.isEmpty) return null;
    PurchaseRecord cheapest = _purchases.first;
    for (final PurchaseRecord p in _purchases) {
      if (p.unitPrice > 0 &&
          (cheapest.unitPrice <= 0 || p.unitPrice < cheapest.unitPrice)) {
        cheapest = p;
      }
    }
    return ItemSearchSummary(
      latest: _purchases.first,
      cheapest: cheapest,
      count: _purchases.length,
      storeCount: _purchases
          .map((PurchaseRecord p) => p.merchantName.toLowerCase().trim())
          .toSet()
          .length,
    );
  }

  /// Nama kategori untuk filter.
  String categoryName(int id) {
    for (final CategoryModel c in _categories) {
      if (c.id == id) return c.name;
    }
    return 'Kategori';
  }

  Future<void> load() async {
    try {
      _categories = (await _categoryRepository.getAll())
          .where((CategoryModel c) => !c.isHidden)
          .toList();
    } catch (_) {
      _categories = <CategoryModel>[];
    }
    await search();
  }

  // ------------------------------------------------------------- kriteria

  /// Mengubah kata kunci; pencarian dijalankan setelah jeda singkat.
  void setQuery(String value) {
    _filter = _filter.withQuery(value);
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(search()));
  }

  void setDateRange(DateTime? from, DateTime? to) =>
      _apply(_filter.withDateRange(from, to));

  void setTotalRange(double? min, double? max) =>
      _apply(_filter.withTotalRange(min, max));

  void setCategories(Set<int> ids) => _apply(_filter.withCategories(ids));

  void toggleCategory(int id) {
    final Set<int> next = Set<int>.of(_filter.categoryIds);
    if (!next.remove(id)) next.add(id);
    setCategories(next);
  }

  void setSort(SearchSort sort) => _apply(_filter.withSort(sort));

  /// Menghapus filter tanggal, total, dan kategori (kata kunci tetap).
  void clearFilters() => _apply(_filter.clearedFilters());

  /// Menghapus semua kriteria.
  void clearAll() => _apply(const TransactionFilter());

  void _apply(TransactionFilter next) {
    _filter = next;
    _timer?.cancel();
    unawaited(search());
  }

  // ------------------------------------------------------------ pencarian

  Future<void> search() async {
    _timer?.cancel();
    final int? userId = _auth.currentUser?.id;
    if (userId == null) {
      _results = <TransactionModel>[];
      _purchases = <PurchaseRecord>[];
      safeNotify();
      return;
    }

    final int token = ++_token;
    final TransactionFilter criteria = _filter;
    _loading = true;
    _error = null;
    safeNotify();

    try {
      final List<TransactionModel> found = await _transactions
          .searchTransactions(userId, criteria, limit: resultLimit);
      final List<PurchaseRecord> items = criteria.hasQuery
          ? await _transactions.searchPurchases(userId, criteria,
              limit: purchaseLimit)
          : <PurchaseRecord>[];
      if (token != _token) return; // Ada pencarian yang lebih baru.
      _results = found;
      _purchases = items;
    } catch (_) {
      if (token != _token) return;
      _error = 'Pencarian gagal. Silakan coba lagi.';
    }
    _loading = false;
    safeNotify();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
