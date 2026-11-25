import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Gradasi batang grafik, dari terang di atas ke pekat di bawah.
class ChartGradients {
  ChartGradients._();

  static const List<Color> normal = [Color(0xFFA7F3D0), Color(0xFF4CCB98)];
  static const List<Color> highlighted = [Color(0xFF2FBF86), AppColors.emerald];
  static const List<Color> selected = [
    Color(0xFF34D399),
    AppColors.emeraldDark
  ];
  static const List<Color> income = [Color(0xFF34D399), AppColors.emerald];
  static const List<Color> expense = [Color(0xFFFCA5A5), Color(0xFFE5484D)];
  static const List<Color> empty = [Color(0x14000000), Color(0x0A000000)];

  static LinearGradient vertical(List<Color> colors) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      );
}

/// Menggambar garis putus-putus dari [a] ke [b].
void paintDashedLine(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint, {
  double dash = 4,
  double gap = 4,
}) {
  final double total = (b - a).distance;
  if (total <= 0) return;
  final Offset dir = (b - a) / total;
  double drawn = 0;
  while (drawn < total) {
    final double end = (drawn + dash).clamp(0.0, total);
    canvas.drawLine(a + dir * drawn, a + dir * end, paint);
    drawn += dash + gap;
  }
}

/// Garis bantu mendatar putus-putus di belakang batang.
class DashedGridPainter extends CustomPainter {
  const DashedGridPainter({this.lines = 3});

  final int lines;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0x2616855A)
      ..strokeWidth = 1;
    for (int i = 0; i < lines; i++) {
      final double y = size.height * i / (lines - 1);
      paintDashedLine(canvas, Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant DashedGridPainter old) => old.lines != lines;
}
