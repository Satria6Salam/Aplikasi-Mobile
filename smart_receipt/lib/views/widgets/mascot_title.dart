import 'package:flutter/material.dart';

import 'mascot.dart';

/// Judul halaman utama dengan maskot di kirinya: judul besar dan satu baris
/// keterangan. Dipakai agar kepala halaman Riwayat, Fitur, dan lainnya seragam.
class MascotTitle extends StatelessWidget {
  const MascotTitle({
    super.key,
    required this.title,
    required this.subtitle,
    required this.mascot,
    this.mascotHeight = 64,
  });

  final String title;
  final String subtitle;
  final MascotKind mascot;
  final double mascotHeight;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        // Muncul dengan pantulan kecil saat halaman dibuka.
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 800),
          curve: Curves.elasticOut,
          builder: (BuildContext context, double t, Widget? child) =>
              Transform.scale(
            scale: 0.5 + 0.5 * t,
            alignment: Alignment.bottomCenter,
            child: child,
          ),
          child: Mascot(kind: mascot, height: mascotHeight, float: true),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.headlineMedium,
              ),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
