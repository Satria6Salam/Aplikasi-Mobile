import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:smart_receipt/data/models/ml_classification_model.dart';
import 'package:smart_receipt/data/models/ocr_result_model.dart';
import 'package:smart_receipt/data/models/parsed_receipt_model.dart';
import 'package:smart_receipt/data/models/qris_pending_model.dart';
import 'package:smart_receipt/data/models/tfidf_feature_model.dart';
import 'package:smart_receipt/data/models/transaction_item_model.dart';
import 'package:smart_receipt/data/models/transaction_model.dart';
import 'package:smart_receipt/data/repositories/qris_pending_repository.dart';
import 'package:smart_receipt/services/geocoding_service.dart';
import 'package:smart_receipt/services/store_location_service.dart';

import '../viewmodels_test.dart' show FakeTransactionRepository;

/// Repository QRIS menunggu struk di memori.
class FakeQrisPendingRepository extends Fake implements QrisPendingRepository {
  final List<QrisPendingModel> items = <QrisPendingModel>[];
  int _nextId = 1;

  @override
  Future<List<QrisPendingModel>> getAll(int userId) async {
    final List<QrisPendingModel> list = items
        .where((QrisPendingModel p) => p.userId == userId)
        .toList()
      ..sort((QrisPendingModel a, QrisPendingModel b) =>
          b.scannedAt.compareTo(a.scannedAt));
    return list;
  }

  @override
  Future<QrisPendingModel?> getById(int id) async {
    for (final QrisPendingModel p in items) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  Future<int> count(int userId) async =>
      items.where((QrisPendingModel p) => p.userId == userId).length;

  @override
  Future<QrisPendingModel> insert(QrisPendingModel pending) async {
    final QrisPendingModel saved = pending.copyWith(id: _nextId++);
    items.add(saved);
    return saved;
  }

  @override
  Future<void> delete(int id) async =>
      items.removeWhere((QrisPendingModel p) => p.id == id);
}

/// Panggilan penyelesaian transaksi QRIS dengan struk.
class CompletedScan {
  CompletedScan({
    required this.transactionId,
    required this.items,
    required this.categoryId,
    this.storeBranch,
    this.storeAddress,
  });

  final int transactionId;
  final List<TransactionItemModel> items;
  final int categoryId;
  final String? storeBranch;
  final String? storeAddress;
}

/// Repository transaksi tiruan dengan dukungan QRIS.
class QrisTransactionRepository extends FakeTransactionRepository {
  final Map<String, int> categoryByMerchantId = <String, int>{};
  final List<CompletedScan> completed = <CompletedScan>[];
  int _nextId = 100;

  @override
  Future<TransactionModel> insert(TransactionModel transaction) async {
    final TransactionModel saved = transaction.copyWith(id: _nextId++);
    stored.add(saved);
    return saved;
  }

  @override
  Future<int?> findCategoryByMerchantId(int userId, String merchantId) async =>
      categoryByMerchantId[merchantId];

  @override
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
    completed.add(CompletedScan(
      transactionId: transactionId,
      items: items,
      categoryId: categoryId,
      storeBranch: storeBranch,
      storeAddress: storeAddress,
    ));
  }
}

/// Layanan lokasi tiruan: hasil pencarian diatur dari luar.
class FakeQrisLocationService extends StoreLocationService {
  FakeQrisLocationService({this.result})
      : super(
          locator: StoreLocator(
            client: NominatimClient(
              minInterval: Duration.zero,
              client: MockClient(
                  (http.Request _) async => http.Response('[]', 200)),
            ),
          ),
        );

  StoreLocation? result;
  final List<String?> cacheKeys = <String?>[];
  final List<bool> gpsFlags = <bool>[];
  final List<StoreLocation> remembered = <StoreLocation>[];
  final List<String?> rememberedAddresses = <String?>[];

  @override
  Future<StoreLocation?> lookup({
    required int userId,
    required String merchantName,
    required StoreAddress address,
    String? cacheAddress,
    bool useGps = false,
  }) async {
    cacheKeys.add(cacheAddress);
    gpsFlags.add(useGps);
    return result;
  }

  @override
  Future<void> remember({
    required int userId,
    required String merchantName,
    required String? address,
    required StoreLocation location,
  }) async {
    remembered.add(location);
    rememberedAddresses.add(address);
  }

  @override
  Future<String?> describe(LatLng point) async => 'Jalan Contoh, Malang';
}

StoreLocation sampleLocation() => StoreLocation(
      point: const LatLng(-7.9667, 112.6326),
      displayName: 'Wizzmie, Jalan Muharto, Malang, Jawa Timur, Indonesia',
      precision: LocationPrecision.store,
      confidence: 0.9,
      source: LocationSource.nearby,
    );
