import 'package:flutter/material.dart';

/// Ikon dua warna: ikon garis berwarna [color] di atas kotak membulat dengan
/// gradasi lembut dan satu bentuk aksen yang lebih terang di sudut. Tetap
/// tajam di semua ukuran dan mengikuti warna tema (tidak berupa gambar).
class DuotoneIcon extends StatelessWidget {
  const DuotoneIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 44,
    this.accent,
    this.onDark = false,
  });

  final IconData icon;

  /// Warna ikon dan dasar gradasi.
  final Color color;

  /// Warna bentuk aksen; bawaannya versi terang dari [color].
  final Color? accent;

  /// Ukuran kotak; ikon di dalamnya sekitar separuhnya.
  final double size;

  /// True di atas permukaan gelap atau kaca: latar putih tembus pandang.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final Color tone = accent ?? Color.lerp(color, Colors.white, 0.45)!;
    final double radius = size * 0.32;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: onDark
              ? const [Color(0x2EFFFFFF), Color(0x14FFFFFF)]
              : [color.withValues(alpha: 0.20), color.withValues(alpha: 0.07)],
        ),
        border: Border.all(
          color:
              onDark ? const Color(0x33FFFFFF) : color.withValues(alpha: 0.18),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Bentuk aksen: lingkaran terang yang menyembul dari sudut kanan bawah.
            Positioned(
              right: -size * 0.16,
              bottom: -size * 0.16,
              child: Container(
                width: size * 0.62,
                height: size * 0.62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone.withValues(alpha: onDark ? 0.40 : 0.42),
                ),
              ),
            ),
            Icon(icon, size: size * 0.5, color: color),
          ],
        ),
      ),
    );
  }
}
