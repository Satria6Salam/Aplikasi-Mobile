import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';

/// Ubin peta OpenStreetMap (gratis; wajib mencantumkan atribusi).
TileLayer osmTileLayer() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.example.smart_receipt',
      maxNativeZoom: 19,
    );

/// Atribusi wajib OpenStreetMap.
Widget osmAttribution() => const SimpleAttributionWidget(
      source: Text('© OpenStreetMap'),
      backgroundColor: Color(0xCCFFFFFF),
    );

/// Ikon pin toko.
class StorePin extends StatelessWidget {
  const StorePin({super.key, this.color = AppColors.emerald, this.size = 40});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.location_on,
      color: color,
      size: size,
      shadows: const <Shadow>[
        Shadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2)),
      ],
    );
  }
}

/// Marker pin yang ujung bawahnya tepat di titik koordinat.
Marker storeMarker(LatLng point, {Color color = AppColors.emerald}) => Marker(
      point: point,
      width: 44,
      height: 44,
      alignment: Alignment.topCenter,
      child: StorePin(color: color),
    );

/// Zoom awal menurut tingkat ketelitian lokasi.
double zoomForConfidence(double confidence) {
  if (confidence >= 0.7) return 17;
  if (confidence >= 0.5) return 15;
  return 13;
}

/// Peta kecil tanpa interaksi berisi satu pin; diketuk untuk membuka peta besar.
class StoreMapPreview extends StatelessWidget {
  const StoreMapPreview({
    super.key,
    required this.point,
    this.zoom = 16,
    this.height = 170,
    this.onTap,
    this.overlayLabel,
  });

  final LatLng point;
  final double zoom;
  final double height;
  final VoidCallback? onTap;

  /// Teks kecil di pojok (mis. "Ketuk untuk ubah").
  final String? overlayLabel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            FlutterMap(
              // Kunci berubah saat titik berubah agar kamera ikut berpindah.
              key: ValueKey<String>(
                  '${point.latitude},${point.longitude},$zoom'),
              options: MapOptions(
                initialCenter: point,
                initialZoom: zoom,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                osmTileLayer(),
                MarkerLayer(markers: <Marker>[storeMarker(point)]),
                osmAttribution(),
              ],
            ),
            if (onTap != null)
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(onTap: onTap),
                ),
              ),
            if (overlayLabel != null)
              Positioned(
                top: 8,
                right: 8,
                child: IgnorePointer(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: AppDecorations.softShadow,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.crosshair,
                            size: 14, color: AppColors.slateDark),
                        const SizedBox(width: 6),
                        Text(
                          overlayLabel!,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: AppColors.slateDark),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
