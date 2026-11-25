import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Latar belakang halaman: gradasi mint dengan lingkaran cahaya hijau.
/// Statis (tanpa animasi) agar ringan saat menggulir.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child, this.dark = false});

  final Widget child;

  /// Gradasi hijau gelap dengan kilau lime (untuk Beranda).
  final bool dark;

  @override
  Widget build(BuildContext context) {
    if (dark) {
      return Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF17935F),
                    AppColors.heroTop,
                    AppColors.heroBottom
                  ],
                  stops: [0, 0.5, 1],
                ),
              ),
            ),
          ),
          const Positioned(
            top: -80,
            right: -70,
            child: _Glow(size: 300, color: Color(0x40C6F432)),
          ),
          const Positioned(
            top: 220,
            left: -120,
            child: _Glow(size: 300, color: Color(0x3334C38A)),
          ),
          child,
        ],
      );
    }
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFFFFFF),
                  Color(0xFFE6F5EC),
                  Color(0xFFD3ECDF)
                ],
              ),
            ),
          ),
        ),
        const Positioned(
          top: 260,
          right: -110,
          child: _Glow(size: 300, color: Color(0x1A34C38A)),
        ),
        const Positioned(
          top: 640,
          left: -120,
          child: _Glow(size: 320, color: Color(0x1216855A)),
        ),
        const Positioned(
          bottom: -60,
          right: -80,
          child: _Glow(size: 260, color: Color(0x1434C38A)),
        ),
        child,
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
