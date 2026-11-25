import 'package:flutter/foundation.dart';

import '../core/constants/db_constants.dart';
import '../data/models/category_model.dart';
import '../data/models/qris_pending_model.dart';
import '../data/models/transaction_model.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/qris_pending_repository.dart';
import '../data/repositories/transaction_repository.dart';
import 'auth_viewmodel.dart';
import 'safe_change_notifier.dart';

/// Daftar QRIS yang menunggu struk: dilengkapi dengan scan struk, diisi
/// nominalnya sendiri, atau dihapus.
class QrisPendingViewModel extends ChangeNotifier with SafeChangeNotifier {
  QrisPendingViewModel({
    required AuthViewModel authViewModel,
    required QrisPendingRepository pendingRepository,
    required TransactionRepository transactionRepository,
    required CategoryRepository categoryRepository,
    this.onChanged,
    DateTime Function()? clock,
  })  : _auth = authViewModel,
        _pending = pendingRepository,
        _transactions = transactionRepository,
        _categoryRepository = categoryRepository,
        _clock = clock ?? DateTime.now;

  static const double maxAmount = 1e12;

  final AuthViewModel _auth;
  final QrisPendingRepository _pending;
  final TransactionRepository _transactions;
  final CategoryRepository _categoryRepository;
  final DateTime Function() _clock;

  /// Dipanggil setelah data berubah (mis. memuat ulang Dasbor).
  final VoidCallback? onChanged;

  List<QrisPendingModel> _items = <QrisPendingModel>[];
  bool _loading = false;
  String? _error;

  List<QrisPendingModel> get items => _items;
  bool get isLoading => _loading;
  String? get errorMessage => _error;

  int? get _userId => _auth.currentUser?.id;

  Future<void> load() async {
    final int? userId = _userId;
    if (userId == null) return;
    _loading = true;
    safeNotify();
    try {
      _items = await _pending.getAll(userId);
      _error = null;
    } catch (_) {
      _error = 'Gagal memuat daftar.';
    }
    _loading = false;
    safeNotify();
  }

  /// Mengisi nominal sendiri: dicatat sebagai transaksi QRIS, lalu dihapus
  /// dari daftar menunggu. Mengembalikan transaksi tersimpan, atau null.
  Future<TransactionModel?> completeWithAmount(
    QrisPendingModel pending, {
    required double amount,
    DateTime? date,
  }) async {
    final int? userId = _userId;
    final int? id = pending.id;
    if (userId == null || id == null) return null;
    if (amount <= 0 || amount > maxAmount) {
      _error =
          amount <= 0 ? 'Jumlah harus lebih dari 0' : 'Jumlah terlalu besar';
      safeNotify();
      return null;
    }
    try {
      final int categoryId = await _categoryOf(pending);
      final DateTime now = _clock();
      final DateTime when = date ?? now;
      final TransactionModel saved = await _transactions.insert(
        TransactionModel(
          userId: userId,
          merchantName: pending.merchantName,
          transactionDate: DateTime(when.year, when.month, when.day),
          totalAmount: amount,
          categoryId: categoryId,
          notes: pending.notes,
          createdAt: now,
          updatedAt: now,
          storeAddress: pending.city,
          latitude: pending.latitude,
          longitude: pending.longitude,
          locationSource: pending.locationSource,
          source: TransactionSource.qris,
          merchantId: pending.merchantId,
        ),
      );
      await _pending.delete(id);
      _items = await _pending.getAll(userId);
      _error = null;
      safeNotify();
      onChanged?.call();
      return saved;
    } catch (_) {
      _error = 'Gagal menyimpan transaksi.';
      safeNotify();
      return null;
    }
  }

  Future<bool> delete(QrisPendingModel pending) async {
    final int? userId = _userId;
    final int? id = pending.id;
    if (userId == null || id == null) return false;
    try {
      await _pending.delete(id);
      _items = await _pending.getAll(userId);
      safeNotify();
      onChanged?.call();
      return true;
    } catch (_) {
      _error = 'Gagal menghapus.';
      safeNotify();
      return false;
    }
  }

  /// Kategori yang dipilih saat memindai; bila tidak ada atau sudah dihapus,
  /// "Lainnya".
  Future<int> _categoryOf(QrisPendingModel pending) async {
    final List<CategoryModel> all = await _categoryRepository.getAll();
    final int? chosen = pending.categoryId;
    if (chosen != null && all.any((CategoryModel c) => c.id == chosen)) {
      return chosen;
    }
    for (final CategoryModel c in all) {
      if (c.name == 'Lainnya' && c.id != null) return c.id!;
    }
    return all.first.id!;
  }
}
