import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'mascot.dart';

/// Kepala halaman Masuk dan Daftar: panel hijau bergradasi bergaya kaca dengan
/// maskot yang melayang. Menggantikan ilustrasi lama agar tampilan seragam
/// dengan Beranda.
class AuthHero extends StatelessWidget {
  const AuthHero({super.key, this.height = 300});

  final double height;

  @override
  Widget build(BuildContext context) {
    final double mascotHeight = (height * 0.62).clamp(90.0, 220.0);
    return Container(
      height: height,
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -60,
            top: -50,
            child: _glow(220, const Color(0x2634C38A)),
          ),
          Positioned(
            left: -70,
            bottom: -80,
            child: _glow(230, const Color(0x1FFFFFFF)),
          ),
          Positioned(
            right: 28,
            bottom: 18,
            child: Mascot(
                kind: MascotKind.edcOk, height: mascotHeight, float: true),
          ),
          Positioned(
            left: 22,
            bottom: 26,
            child: Transform.rotate(
              angle: -0.12,
              child: Mascot(
                  kind: MascotKind.receipt,
                  height: mascotHeight * 0.5,
                  float: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}
