import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import 'chart_style.dart';

/// Satu titik pada grafik harga.
class PricePoint {
  const PricePoint({required this.date, required this.price});

  final DateTime date;
  final double price;
}

/// Grafik garis harga satuan dari waktu ke waktu. Titik termurah ditandai
/// hijau dan termahal merah; sumbu X mengikuti jarak tanggal sebenarnya.
class PriceLineChart extends StatelessWidget {
  const PriceLineChart({super.key, required this.points, this.height = 180});

  /// Harus terurut dari tanggal terlama.
  final List<PricePoint> points;
  final double height;

  /// Format singkat: 26.500 -> "26,5rb", 1.250.000 -> "1,25jt".
  static String compact(double value) {
    String trim(double v, int digits) {
      final String s = v.toStringAsFixed(digits);
      final String t = s.contains('.')
          ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')
          : s;
      return t.replaceAll('.', ',');
    }

    if (value >= 1000000) return '${trim(value / 1000000, 2)}jt';
    if (value >= 1000) return '${trim(value / 1000, 1)}rb';
    return trim(value, 0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _PriceChartPainter(
          points: points,
          labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.coolGray,
                    fontSize: 10,
                  ) ??
              const TextStyle(fontSize: 10, color: AppColors.coolGray),
        ),
      ),
    );
  }
}

class _PriceChartPainter extends CustomPainter {
  _PriceChartPainter({required this.points, required this.labelStyle});

  final List<PricePoint> points;
  final TextStyle labelStyle;

  static const double _left = 46;
  static const double _right = 12;
  static const double _top = 14;
  static const double _bottom = 26;

  TextPainter _text(String text, {TextAlign align = TextAlign.left}) {
    return TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final Rect area = Rect.fromLTRB(
      _left,
      _top,
      size.width - _right,
      size.height - _bottom,
    );

    double minPrice = points.first.price;
    double maxPrice = points.first.price;
    for (final PricePoint p in points) {
      if (p.price < minPrice) minPrice = p.price;
      if (p.price > maxPrice) maxPrice = p.price;
    }
    // Rentang sumbu Y diberi ruang agar titik tidak menempel di tepi.
    double low = minPrice;
    double high = maxPrice;
    if ((high - low).abs() < 1) {
      low -= 1;
      high += 1;
    }
    final double pad = (high - low) * 0.12;
    low -= pad;
    high += pad;

    // Garis bantu dan label harga.
    final Paint grid = Paint()
      ..color = const Color(0x2616855A)
      ..strokeWidth = 1;
    for (int i = 0; i <= 2; i++) {
      final double y = area.top + area.height * i / 2;
      paintDashedLine(
          canvas, Offset(area.left, y), Offset(area.right, y), grid);
      final double value = high - (high - low) * i / 2;
      final TextPainter label = _text(PriceLineChart.compact(value));
      label.paint(
          canvas, Offset(area.left - label.width - 6, y - label.height / 2));
    }

    final int t0 = points.first.date.millisecondsSinceEpoch;
    final int t1 = points.last.date.millisecondsSinceEpoch;
    double xOf(int index) {
      if (points.length == 1 || t1 == t0) return area.center.dx;
      final double f =
          (points[index].date.millisecondsSinceEpoch - t0) / (t1 - t0);
      return area.left + area.width * f;
    }

    double yOf(double price) =>
        area.bottom - area.height * (price - low) / (high - low);

    // Garis melengkung dengan area berwarna di bawahnya.
    if (points.length > 1) {
      final Path path = Path()..moveTo(xOf(0), yOf(points.first.price));
      for (int i = 1; i < points.length; i++) {
        final double x0 = xOf(i - 1);
        final double y0 = yOf(points[i - 1].price);
        final double x1 = xOf(i);
        final double y1 = yOf(points[i].price);
        final double mid = (x0 + x1) / 2;
        path.cubicTo(mid, y0, mid, y1, x1, y1);
      }
      final Path fill = Path.from(path)
        ..lineTo(xOf(points.length - 1), area.bottom)
        ..lineTo(xOf(0), area.bottom)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x5534C38A), Color(0x0034C38A)],
          ).createShader(area),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.emerald.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawPath(
        path,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF34C38A), AppColors.emerald],
          ).createShader(area)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    // Titik: termurah hijau tua, termahal merah, terakhir lebih besar.
    final bool varies = maxPrice - minPrice >= 1;
    for (int i = 0; i < points.length; i++) {
      final PricePoint p = points[i];
      Color color = AppColors.emerald;
      if (varies && p.price == minPrice) color = AppColors.forest;
      if (varies && p.price == maxPrice) color = AppColors.error;
      final Offset c = Offset(xOf(i), yOf(p.price));
      final bool last = i == points.length - 1;
      if (last) {
        canvas.drawCircle(
            c, 11, Paint()..color = color.withValues(alpha: 0.18));
      }
      canvas.drawCircle(c, last ? 6 : 4.5, Paint()..color = AppColors.white);
      canvas.drawCircle(c, last ? 4.5 : 3.2, Paint()..color = color);
    }

    // Tanggal awal dan akhir.
    final TextPainter first = _text(AppFormatters.shortDate(points.first.date));
    first.paint(canvas, Offset(area.left, size.height - first.height - 2));
    if (points.length > 1 && t1 != t0) {
      final TextPainter last = _text(AppFormatters.shortDate(points.last.date));
      last.paint(canvas,
          Offset(area.right - last.width, size.height - last.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant _PriceChartPainter old) =>
      old.points != points || old.labelStyle != labelStyle;
}
