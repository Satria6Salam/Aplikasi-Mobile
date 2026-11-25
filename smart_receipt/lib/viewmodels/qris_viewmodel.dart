import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants/db_constants.dart';
import '../data/models/category_model.dart';
import '../data/models/qris_pending_model.dart';
import '../data/models/transaction_model.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/qris_pending_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../services/duplicate_detector.dart';
import '../services/qris_parser.dart';
import '../services/store_location_service.dart';
import 'auth_viewmodel.dart';
import 'safe_change_notifier.dart';

export '../services/qris_parser.dart' show QrisData, QrisError;

/// Alasan kategori yang dipilih, untuk ditampilkan agar pengguna paham.
enum CategorySuggestion { history, businessType, none }

/// Tahapan pencarian lokasi toko dari QRIS.
enum QrisLocationStatus { idle, searching, found, notFound }

/// Hasil menyimpan: transaksi final, atau catatan yang menunggu struk.
class QrisSaveResult {
  const QrisSaveResult.transaction(this.transaction) : pending = null;
  const QrisSaveResult.pending(this.pending) : transaction = null;

  final TransactionModel? transaction;
  final QrisPendingModel? pending;

  bool get isPending => pending != null;
}

/// Mengelola alur Scan QRIS: membaca kode, menyiapkan formulir (kategori dari
/// riwayat toko atau jenis usaha, lokasi dari GPS dan kota), memeriksa
/// transaksi ganda, lalu menyimpan sebagai transaksi atau menunggu struk.
///
/// QRIS statis tidak memuat nominal, jadi pengguna mengetik sendiri, atau
/// memilih mengisinya dari struk nanti. QRIS dinamis memuat nominal.
class QrisViewModel extends ChangeNotifier with SafeChangeNotifier {
  QrisViewModel({
    required AuthViewModel authViewModel,
    required TransactionRepository transactionRepository,
    required CategoryRepository categoryRepository,
    required QrisPendingRepository pendingRepository,
    StoreLocationService? storeLocationService,
    QrisParser parser = const QrisParser(),
    this.onSaved,
    DateTime Function()? clock,
  })  : _auth = authViewModel,
        _transactions = transactionRepository,
        _categoryRepository = categoryRepository,
        _pendingRepository = pendingRepository,
        _locationService = storeLocationService,
        _parser = parser,
        _clock = clock ?? DateTime.now,
        _detector = DuplicateDetector(transactionRepository);

  static const double maxAmount = 1e12;

  final AuthViewModel _auth;
  final TransactionRepository _transactions;
  final CategoryRepository _categoryRepository;
  final QrisPendingRepository _pendingRepository;
  final StoreLocationService? _locationService;
  final QrisParser _parser;
  final DateTime Function() _clock;
  final DuplicateDetector _detector;

  /// Dipanggil setelah sesuatu tersimpan (mis. memuat ulang Dasbor).
  final VoidCallback? onSaved;

  QrisData? _data;
  String? _scanError;
  String? _lastRejected;
  List<CategoryModel> _categories = <CategoryModel>[];
  int? _categoryId;
  int? _suggestedCategoryId;
  CategorySuggestion _suggestion = CategorySuggestion.none;
  double? _amount;
  bool _waitForReceipt = false;
  DateTime _date = DateTime.now();
  String _notes = '';
  List<DuplicateMatch> _duplicates = const <DuplicateMatch>[];
  StoreLocation? _location;
  QrisLocationStatus _locationStatus = QrisLocationStatus.idle;
  bool _saving = false;
  String? _formError;
  int _token = 0;

  QrisData? get data => _data;

  /// Pesan galat pemindaian (kode bukan QRIS/rusak); null bila tidak ada.
  String? get scanError => _scanError;
  List<CategoryModel> get categories => _categories;
  int? get categoryId => _categoryId;
  CategorySuggestion get suggestion => _suggestion;
  double? get amount => _amount;
  bool get waitForReceipt => _waitForReceipt;
  DateTime get date => _date;
  List<DuplicateMatch> get duplicates => _duplicates;
  StoreLocation? get location => _location;
  QrisLocationStatus get locationStatus => _locationStatus;
  bool get isSaving => _saving;
  String? get formError => _formError;

  bool get hasData => _data != null;

  /// True bila nominal tidak ada pada QR dan harus diisi pengguna.
  bool get needsAmount => _data != null && !_data!.hasAmount;

  /// Nama kategori terpilih.
  String get categoryName {
    for (final CategoryModel c in _categories) {
      if (c.id == _categoryId) return c.name;
    }
    return 'Lainnya';
  }

  int? get _userId => _auth.currentUser?.id;

  // ------------------------------------------------------------ pemindaian

  /// Dipanggil pemindai untuk setiap kode yang terbaca. Mengembalikan true
  /// bila kodenya QRIS valid dan formulir siap.
  Future<bool> onScanned(String payload) async {
    if (_data != null || _saving) return false;
    // Kode rusak yang sama dibaca berulang oleh kamera: abaikan.
    if (payload == _lastRejected) return false;

    final QrisData parsed;
    try {
      parsed = _parser.parse(payload);
    } on QrisParseException catch (e) {
      _lastRejected = payload;
      _scanError = e.message;
      safeNotify();
      return false;
    }

    _scanError = null;
    _lastRejected = null;
    _formError = null;
    _data = parsed;
    _amount = parsed.totalAmount;
    _waitForReceipt = false;
    _date = _today();
    _notes = '';
    _duplicates = const <DuplicateMatch>[];
    _location = null;
    _locationStatus = QrisLocationStatus.idle;
    safeNotify();

    await _prepare(parsed);
    return true;
  }

  Future<void> _prepare(QrisData data) async {
    final int token = ++_token;
    final int? userId = _userId;

    try {
      _categories = (await _categoryRepository.getAll())
          .where((CategoryModel c) => !c.isHidden)
          .toList();
    } catch (_) {
      _categories = <CategoryModel>[];
    }

    // Kategori: koreksi terakhir untuk toko yang sama lebih dipercaya
    // daripada tebakan dari jenis usaha.
    int? chosen;
    CategorySuggestion why = CategorySuggestion.none;
    final String? nmid = data.merchantId;
    if (userId != null && nmid != null) {
      try {
        final int? remembered =
            await _transactions.findCategoryByMerchantId(userId, nmid);
        if (remembered != null &&
            _categories.any((CategoryModel c) => c.id == remembered)) {
          chosen = remembered;
          why = CategorySuggestion.history;
        }
      } catch (_) {}
    }
    if (chosen == null) {
      chosen = _categoryByName(data.categoryName)?.id ??
          _categoryByName('Lainnya')?.id;
      why = chosen == null
          ? CategorySuggestion.none
          : CategorySuggestion.businessType;
    }
    if (token != _token) return;
    _categoryId = chosen;
    _suggestedCategoryId = chosen;
    _suggestion = why;
    safeNotify();

    await Future.wait(<Future<void>>[checkDuplicates(), lookupLocation()]);
  }

  CategoryModel? _categoryByName(String name) {
    for (final CategoryModel c in _categories) {
      if (c.name.toLowerCase() == name.toLowerCase()) return c;
    }
    return null;
  }

  /// Kembali ke pemindai untuk memindai kode lain.
  void reset() {
    _token++;
    _data = null;
    _scanError = null;
    _lastRejected = null;
    _formError = null;
    _amount = null;
    _waitForReceipt = false;
    _categoryId = null;
    _duplicates = const <DuplicateMatch>[];
    _location = null;
    _locationStatus = QrisLocationStatus.idle;
    _saving = false;
    safeNotify();
  }

  void clearScanError() {
    if (_scanError == null) return;
    _scanError = null;
    safeNotify();
  }

  // -------------------------------------------------------------- formulir

  DateTime _today() {
    final DateTime n = _clock();
    return DateTime(n.year, n.month, n.day);
  }

  void selectCategory(int id) {
    _categoryId = id;
    _formError = null;
    safeNotify();
  }

  void setAmount(double? value) {
    _amount = value;
    _formError = null;
    safeNotify();
    unawaited(checkDuplicates());
  }

  /// "Isi nominal dari struk nanti": hanya untuk QRIS tanpa nominal.
  void setWaitForReceipt(bool value) {
    if (!needsAmount) return;
    _waitForReceipt = value;
    _formError = null;
    safeNotify();
  }

  void setDate(DateTime? value) {
    if (value == null) return;
    _date = DateTime(value.year, value.month, value.day);
    safeNotify();
    unawaited(checkDuplicates());
  }

  void setNotes(String value) => _notes = value;

  // ----------------------------------------------------- struk ganda & lokasi

  /// Memeriksa apakah transaksi serupa (tanggal, total, toko) sudah ada.
  Future<void> checkDuplicates() async {
    final QrisData? data = _data;
    final int? userId = _userId;
    final double? amount = _amount;
    if (data == null || userId == null || amount == null || amount <= 0) {
      if (_duplicates.isNotEmpty) {
        _duplicates = const <DuplicateMatch>[];
        safeNotify();
      }
      return;
    }
    try {
      final List<DuplicateMatch> found = await _detector.find(
        userId: userId,
        date: _date,
        total: amount,
        merchantName: data.merchantName,
        itemNames: const <String>[],
      );
      if (!identical(data, _data)) return;
      _duplicates = found;
    } catch (_) {
      _duplicates = const <DuplicateMatch>[];
    }
    safeNotify();
  }

  /// Mencari titik toko: GPS (Anda sedang di toko), nama toko, dan kota.
  Future<void> lookupLocation() async {
    final QrisData? data = _data;
    final StoreLocationService? service = _locationService;
    final int? userId = _userId;
    if (data == null || service == null || userId == null) return;

    final int token = _token;
    _locationStatus = QrisLocationStatus.searching;
    safeNotify();
    try {
      final StoreLocation? found = await service.lookup(
        userId: userId,
        merchantName: data.merchantName,
        address: StoreAddress(
          branchName: data.storeLabel,
          city: data.city,
          postalCode: data.postalCode,
        ),
        cacheAddress: _cacheKey(data),
        useGps: true, // Memindai QRIS terjadi di toko.
      );
      if (token != _token || !identical(data, _data)) return;
      _location = found;
      _locationStatus = found == null
          ? QrisLocationStatus.notFound
          : QrisLocationStatus.found;
    } catch (_) {
      if (token != _token) return;
      _locationStatus = QrisLocationStatus.notFound;
    }
    safeNotify();
  }

  String? _cacheKey(QrisData data) =>
      data.merchantId == null ? null : 'qris:${data.merchantId}';

  // ---------------------------------------------------------------- simpan

  /// Menyimpan sebagai transaksi (nominal diketahui) atau QRIS menunggu struk.
  /// Mengembalikan null bila formulir belum valid; lihat [formError].
  Future<QrisSaveResult?> save() async {
    final QrisData? data = _data;
    final int? userId = _userId;
    if (data == null || _saving) return null;
    if (userId == null) {
      _formError = 'Sesi berakhir. Silakan login kembali.';
      safeNotify();
      return null;
    }
    if (_categoryId == null) {
      _formError = 'Pilih kategori terlebih dahulu';
      safeNotify();
      return null;
    }

    final bool waiting = needsAmount && _waitForReceipt;
    final double? amount = _amount;
    if (!waiting) {
      if (amount == null || amount <= 0) {
        _formError = 'Isi jumlah yang Anda bayarkan';
        safeNotify();
        return null;
      }
      if (amount > maxAmount) {
        _formError = 'Jumlah terlalu besar';
        safeNotify();
        return null;
      }
    }

    _saving = true;
    _formError = null;
    safeNotify();
    try {
      final DateTime now = _clock();
      final StoreLocation? loc = _location;
      final String notes = _notes.trim();

      final QrisSaveResult result;
      if (waiting) {
        final QrisPendingModel saved = await _pendingRepository.insert(
          QrisPendingModel(
            userId: userId,
            merchantName: data.merchantName,
            city: data.city,
            merchantId: data.merchantId,
            mcc: data.mcc,
            categoryId: _categoryId,
            latitude: loc?.point.latitude,
            longitude: loc?.point.longitude,
            locationSource: loc?.source,
            notes: notes.isEmpty ? null : notes,
            scannedAt: now,
          ),
        );
        result = QrisSaveResult.pending(saved);
      } else {
        final TransactionModel saved = await _transactions.insert(
          TransactionModel(
            userId: userId,
            merchantName: data.merchantName,
            transactionDate: _date,
            totalAmount: amount!,
            categoryId: _categoryId!,
            isManualEdit: _categoryId != _suggestedCategoryId,
            notes: notes.isEmpty ? null : notes,
            createdAt: now,
            updatedAt: now,
            storeBranch: data.storeLabel,
            storeAddress: data.city,
            latitude: loc?.point.latitude,
            longitude: loc?.point.longitude,
            locationPrecision: loc?.precision.name,
            locationSource: loc?.source,
            source: TransactionSource.qris,
            merchantId: data.merchantId,
          ),
        );
        result = QrisSaveResult.transaction(saved);
      }

      // Ingat titik toko untuk NMID ini agar pemindaian berikutnya instan.
      final String? key = _cacheKey(data);
      if (loc != null && key != null) {
        await _locationService?.remember(
          userId: userId,
          merchantName: data.merchantName,
          address: key,
          location: loc,
        );
      }
      _saving = false;
      safeNotify();
      onSaved?.call();
      return result;
    } catch (_) {
      _saving = false;
      _formError = 'Gagal menyimpan. Silakan coba lagi.';
      safeNotify();
      return null;
    }
  }
}
