import 'package:flutter/material.dart';

import '../../core/theme/app_decorations.dart';
import 'shimmer_sweep.dart';

/// Kartu standar SmartReceipt: gradasi hijau, tepi berkilau, dan kilau cahaya
/// yang menyapu pelan. Dipakai untuk kartu-kartu utama agar tampilannya seragam.
class AnimatedCard extends StatelessWidget {
  const AnimatedCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.radius = AppRadius.card,
    this.width,
    this.phase = 0,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double? width;
  final double phase;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: AppDecorations.card(radius: radius),
      child: Stack(
        children: [
          Padding(padding: padding, child: child),
          ShimmerSweep(radius: radius, phase: phase),
        ],
      ),
    );
  }
}
