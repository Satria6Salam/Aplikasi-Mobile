import 'package:latlong2/latlong.dart';

import '../data/repositories/store_location_repository.dart';
import 'device_location_service.dart';
import 'geocoding_service.dart';
import 'store_address_extractor.dart';

export 'device_location_service.dart'
    show DeviceLocationResult, DevicePosition, LocationAccess;
export 'geocoding_service.dart'
    show GeocodingException, LocationSource, StoreLocation;
export 'store_address_extractor.dart'
    show LocationPrecision, LocationPrecisionLabel, StoreAddress;

/// Penentu lokasi toko: cache riwayat -> API geocoding (alamat struk + GPS)
/// -> posisi GPS sebagai cadangan.
class StoreLocationService {
  StoreLocationService({
    required StoreLocator locator,
    StoreLocationRepository? cache,
    DeviceLocationService device = const DeviceLocationService(),
    StoreAddressExtractor extractor = const StoreAddressExtractor(),
  })  : _locator = locator,
        _cache = cache,
        _device = device,
        _extractor = extractor;

  final StoreLocator _locator;
  final StoreLocationRepository? _cache;
  final DeviceLocationService _device;
  final StoreAddressExtractor _extractor;

  /// GPS dengan radius ketidakpastian di atas ini tidak dipakai sebagai patokan.
  static const double maxGpsAccuracyMeters = 300;

  /// Mengurai ulang alamat yang disunting pengguna (satu baris berkoma).
  StoreAddress parseAddress(String text, {String? merchantName}) {
    final String oneLine = text.replaceAll(RegExp(r'\s*\n\s*'), ', ').trim();
    if (oneLine.isEmpty) return StoreAddress.empty;
    return _extractor.extract(oneLine, merchantName: merchantName);
  }

  /// Mencari lokasi toko. [useGps] true bila struk kemungkinan besar difoto
  /// di toko (dari kamera, pada hari transaksi), sehingga posisi perangkat
  /// boleh dipakai untuk menyaring kandidat. [cacheAddress] adalah alamat
  /// asli struk untuk mencari riwayat; null berarti cache dilewati.
  Future<StoreLocation?> lookup({
    required int userId,
    required String merchantName,
    required StoreAddress address,
    String? cacheAddress,
    bool useGps = false,
  }) async {
    final String merchant = merchantName.trim();

    final StoreLocationRepository? cache = _cache;
    if (cache != null && merchant.isNotEmpty && cacheAddress != null) {
      try {
        final StoreLocation? hit =
            await cache.find(userId, merchant, cacheAddress);
        if (hit != null) return hit;
      } catch (_) {
        // Cache rusak/tidak tersedia: lanjut ke API.
      }
    }

    LatLng? nearby;
    if (useGps) {
      final DeviceLocationResult gps = await _device.current();
      final DevicePosition? p = gps.position;
      if (p != null && p.accuracyMeters <= maxGpsAccuracyMeters) {
        nearby = p.point;
      }
    }

    if (address.isEmpty && nearby == null) return null;
    return _locator.locate(
      address: address,
      merchantName: merchant,
      nearby: nearby,
    );
  }

  /// Posisi perangkat sekarang (tombol "Pakai lokasi saya").
  Future<DeviceLocationResult> currentPosition() => _device.current();

  Future<bool> openLocationSettings() => _device.openSettings();

  /// Alamat menurut peta untuk titik pilihan pengguna; null bila gagal.
  Future<String?> describe(LatLng point) async {
    try {
      return await _locator.describe(point);
    } on GeocodingException {
      return null;
    }
  }

  /// Mengingat lokasi yang sudah dipastikan pengguna untuk struk berikutnya.
  /// [address] adalah alamat asli struk (kunci cache); tanpa alamat, lokasi
  /// tidak diingat agar cabang lain dari jaringan yang sama tidak tertukar.
  Future<void> remember({
    required int userId,
    required String merchantName,
    required String? address,
    required StoreLocation location,
  }) async {
    final StoreLocationRepository? cache = _cache;
    if (cache == null ||
        merchantName.trim().isEmpty ||
        address == null ||
        address.trim().isEmpty) {
      return;
    }
    try {
      await cache.save(
        userId: userId,
        merchant: merchantName.trim(),
        address: address,
        location: location.source == LocationSource.cache
            ? location
            : location.copyWith(
                confidence: location.source == LocationSource.manual
                    ? 0.95
                    : location.confidence,
              ),
      );
    } catch (_) {
      // Gagal mengingat tidak membatalkan transaksi.
    }
  }
}
