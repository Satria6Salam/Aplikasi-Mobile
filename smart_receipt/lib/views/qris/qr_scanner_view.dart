import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../services/store_location_service.dart';
import '../widgets/custom_button.dart';

/// Pembuat tampilan pemindai kode QR. [onCode] dipanggil untuk setiap kode
/// yang terbaca. Dibuat sebagai fungsi agar pengujian bisa mengganti kamera
/// dengan tiruan.
typedef QrScannerBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onCode,
);

/// Pemindai bawaan: kamera belakang, hanya format QR.
Widget cameraQrScanner(BuildContext context, ValueChanged<String> onCode) =>
    _CameraQrScanner(onCode: onCode);

class _CameraQrScanner extends StatefulWidget {
  const _CameraQrScanner({required this.onCode});

  final ValueChanged<String> onCode;

  @override
  State<_CameraQrScanner> createState() => _CameraQrScannerState();
}

class _CameraQrScannerState extends State<_CameraQrScanner> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 400,
  );
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final Barcode barcode in capture.barcodes) {
      final String? raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        widget.onCode(raw);
        return;
      }
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (mounted) setState(() => _torch = !_torch);
    } catch (_) {
      // Perangkat tanpa lampu kilat: abaikan.
    }
  }

  Widget _error(BuildContext context, MobileScannerException error) {
    final bool denied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    final String message = denied
        ? 'Izin kamera ditolak. Aktifkan izin kamera untuk memindai QRIS.'
        : error.errorCode == MobileScannerErrorCode.unsupported
            ? 'Perangkat ini tidak mendukung pemindaian kamera.'
            : 'Kamera tidak dapat dibuka. Coba tutup lalu buka kembali layar ini.';
    return Container(
      color: AppColors.slateDark,
      padding: const EdgeInsets.all(AppSpacing.lg),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.camera, size: 40, color: AppColors.white),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.white),
          ),
          if (denied) ...[
            const SizedBox(height: AppSpacing.md),
            CustomButton(
              label: 'Buka Pengaturan',
              variant: CustomButtonVariant.secondary,
              onPressed: () =>
                  context.read<StoreLocationService>().openLocationSettings(),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: _error,
        ),
        Positioned(
          right: AppSpacing.md,
          top: AppSpacing.md,
          child: IconButton.filled(
            tooltip: _torch ? 'Matikan lampu' : 'Nyalakan lampu',
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
            ),
            onPressed: _toggleTorch,
            icon: Icon(_torch ? AppIcons.flashlightOff : AppIcons.flashlight),
          ),
        ),
      ],
    );
  }
}
