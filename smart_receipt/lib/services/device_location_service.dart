import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Hasil pengambilan posisi perangkat.
enum LocationAccess { granted, denied, deniedForever, serviceDisabled, failed }

class DevicePosition {
  const DevicePosition(this.point, this.accuracyMeters);

  final LatLng point;

  /// Radius ketidakpastian GPS (meter).
  final double accuracyMeters;
}

class DeviceLocationResult {
  const DeviceLocationResult(this.access, [this.position]);

  final LocationAccess access;
  final DevicePosition? position;

  String? get message => switch (access) {
        LocationAccess.granted => null,
        LocationAccess.denied => 'Izin lokasi ditolak.',
        LocationAccess.deniedForever =>
          'Izin lokasi ditolak permanen. Aktifkan lewat Pengaturan aplikasi.',
        LocationAccess.serviceDisabled =>
          'GPS sedang mati. Nyalakan layanan lokasi terlebih dahulu.',
        LocationAccess.failed => 'Posisi GPS tidak dapat dibaca.',
      };
}

/// Pembungkus GPS perangkat (paket geolocator). Dibuat sebagai kelas agar
/// dapat diganti tiruan pada pengujian.
class DeviceLocationService {
  const DeviceLocationService();

  /// Posisi sekarang. [request] false berarti tidak memunculkan dialog izin
  /// (hanya dipakai bila izin sudah pernah diberikan).
  Future<DeviceLocationResult> current({bool request = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const DeviceLocationResult(LocationAccess.serviceDisabled);
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && request) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const DeviceLocationResult(LocationAccess.deniedForever);
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        return const DeviceLocationResult(LocationAccess.denied);
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 12),
          ),
        );
      } on TimeoutException {
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null) {
        return const DeviceLocationResult(LocationAccess.failed);
      }
      return DeviceLocationResult(
        LocationAccess.granted,
        DevicePosition(
          LatLng(position.latitude, position.longitude),
          position.accuracy,
        ),
      );
    } catch (_) {
      return const DeviceLocationResult(LocationAccess.failed);
    }
  }

  Future<bool> openSettings() => Geolocator.openAppSettings();
}
