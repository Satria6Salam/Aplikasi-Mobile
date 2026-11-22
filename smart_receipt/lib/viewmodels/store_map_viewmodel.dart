import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../data/models/transaction_model.dart';
import '../data/repositories/transaction_repository.dart';
import 'auth_viewmodel.dart';
import 'safe_change_notifier.dart';

/// Satu toko (titik) di peta beserta ringkasan belanja di sana.
class StorePlace {
  StorePlace({
    required this.point,
    required this.merchantName,
    this.branch,
    this.address,
  });

  final LatLng point;
  final String merchantName;
  final String? branch;
  final String? address;
  final List<TransactionModel> transactions = <TransactionModel>[];

  double get totalSpent => transactions.fold<double>(
      0, (double sum, TransactionModel t) => sum + t.totalAmount);

  int get visits => transactions.length;

  DateTime get lastVisit => transactions
      .map((TransactionModel t) => t.transactionDate)
      .reduce((DateTime a, DateTime b) => a.isAfter(b) ? a : b);

  String get title =>
      branch == null || branch!.isEmpty ? merchantName : '$merchantName $branch';
}

/// Data layar Peta Toko: transaksi yang punya koordinat, dikelompokkan per toko.
class StoreMapViewModel extends ChangeNotifier with SafeChangeNotifier {
  StoreMapViewModel({
    required AuthViewModel authViewModel,
    required TransactionRepository transactionRepository,
  })  : _auth = authViewModel,
        _repository = transactionRepository;

  final AuthViewModel _auth;
  final TransactionRepository _repository;

  /// Titik dalam radius ini (meter) dengan nama sama dianggap toko yang sama.
  static const double sameStoreMeters = 60;

  bool _loading = false;
  String? _error;
  List<StorePlace> _places = <StorePlace>[];
  StorePlace? _selected;

  bool get isLoading => _loading;
  String? get errorMessage => _error;

  /// Diurutkan dari total belanja terbesar.
  List<StorePlace> get places => _places;
  StorePlace? get selected => _selected;

  Future<void> load() async {
    final int? userId = _auth.currentUser?.id;
    if (userId == null) return;
    _loading = true;
    _error = null;
    safeNotify();
    try {
      final List<TransactionModel> rows =
          await _repository.getWithLocation(userId);
      _places = group(rows);
      _selected = null;
    } catch (_) {
      _error = 'Gagal memuat peta toko.';
    }
    _loading = false;
    safeNotify();
  }

  void select(StorePlace? place) {
    _selected = place;
    safeNotify();
  }

  /// Mengelompokkan transaksi per toko (nama sama dan titik berdekatan).
  static List<StorePlace> group(List<TransactionModel> rows) {
    const Distance distance = Distance();
    final List<StorePlace> places = <StorePlace>[];
    for (final TransactionModel t in rows) {
      final double? lat = t.latitude;
      final double? lng = t.longitude;
      if (lat == null || lng == null) continue;
      final LatLng point = LatLng(lat, lng);
      final String name = t.merchantName.trim().toLowerCase();
      StorePlace? match;
      for (final StorePlace p in places) {
        if (p.merchantName.trim().toLowerCase() == name &&
            distance.as(LengthUnit.Meter, p.point, point) <= sameStoreMeters) {
          match = p;
          break;
        }
      }
      match ??= () {
        final StorePlace created = StorePlace(
          point: point,
          merchantName: t.merchantName,
          branch: t.storeBranch,
          address: t.storeAddress,
        );
        places.add(created);
        return created;
      }();
      match.transactions.add(t);
    }
    places.sort(
        (StorePlace a, StorePlace b) => b.totalSpent.compareTo(a.totalSpent));
    return places;
  }
}
