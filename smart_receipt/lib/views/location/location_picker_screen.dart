import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../services/store_location_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/store_map.dart';

/// Membuka peta layar penuh untuk memilih titik toko. Mengembalikan titik
/// pilihan, atau null bila dibatalkan.
Future<LatLng?> showLocationPicker(
  BuildContext context, {
  LatLng? initial,
  double initialZoom = 17,
  String? title,
}) {
  return Navigator.of(context).push<LatLng>(
    MaterialPageRoute<LatLng>(
      fullscreenDialog: true,
      builder: (_) => LocationPickerScreen(
        initial: initial,
        initialZoom: initialZoom,
        title: title,
      ),
    ),
  );
}

/// Peta dengan pin tetap di tengah: pengguna menggeser peta sampai pin
/// tepat di atas toko, lalu menekan "Pakai Titik Ini".
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.initial,
    this.initialZoom = 17,
    this.title,
  });

  final LatLng? initial;
  final double initialZoom;
  final String? title;

  /// Pusat Indonesia bila belum ada titik awal.
  static const LatLng indonesia = LatLng(-2.5, 118.0);

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _controller = MapController();
  late LatLng _center = widget.initial ?? LocationPickerScreen.indonesia;
  bool _locating = false;

  Future<void> _goToMyLocation() async {
    final StoreLocationService service = context.read<StoreLocationService>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _locating = true);
    final DeviceLocationResult result = await service.currentPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    final DevicePosition? position = result.position;
    if (position == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Posisi tidak tersedia'),
          action: result.access == LocationAccess.deniedForever
              ? SnackBarAction(
                  label: 'Pengaturan',
                  onPressed: service.openLocationSettings,
                )
              : null,
        ),
      );
      return;
    }
    _controller.move(position.point, 18);
    setState(() => _center = position.point);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Atur Lokasi Toko')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: _center,
              initialZoom:
                  widget.initial == null ? 4.5 : widget.initialZoom,
              minZoom: 3,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onPositionChanged: (MapCamera camera, bool hasGesture) {
                _center = camera.center;
              },
              onTap: (TapPosition _, LatLng point) {
                _controller.move(point, _controller.camera.zoom);
                setState(() => _center = point);
              },
            ),
            children: [
              osmTileLayer(),
              osmAttribution(),
            ],
          ),
          // Pin tetap di tengah; ujung bawahnya menandai titik terpilih.
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 44),
                child: StorePin(size: 48),
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.md,
            left: AppSpacing.md,
            right: AppSpacing.md,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: AppDecorations.card(),
              child: Row(
                children: [
                  Icon(AppIcons.info, size: 18, color: AppColors.emerald),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Geser peta sampai pin tepat di atas toko, atau ketuk lokasi toko di peta.',
                      style: textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: AppSpacing.md,
            bottom: 112,
            child: FloatingActionButton.small(
              heroTag: 'picker-locate',
              backgroundColor: AppColors.white,
              foregroundColor: AppColors.slateDark,
              onPressed: _locating ? null : _goToMyLocation,
              tooltip: 'Lokasi saya',
              child: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(AppIcons.locate),
            ),
          ),
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.md,
            child: SafeArea(
              top: false,
              child: CustomButton(
                label: 'Pakai Titik Ini',
                icon: AppIcons.check,
                onPressed: () => Navigator.of(context).pop(_center),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
