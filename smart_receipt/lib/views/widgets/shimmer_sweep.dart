import 'package:flutter/material.dart';

/// Kilau cahaya lembut yang menyapu kartu dari kiri ke kanan secara berkala.
///
/// Letakkan sebagai lapisan teratas di dalam `Stack` kartu. Tidak menangkap
/// sentuhan. [radius] harus sama dengan sudut kartunya agar kilau terpotong
/// rapi.
class ShimmerSweep extends StatefulWidget {
  const ShimmerSweep({
    super.key,
    this.radius = 20,
    this.period = const Duration(seconds: 7),
    this.phase = 0,
  });

  final double radius;
  final Duration period;

  /// Geser awal (0..1) agar kartu-kartu tidak berkilau serempak.
  final double phase;

  @override
  State<ShimmerSweep> createState() => _ShimmerSweepState();
}

class _ShimmerSweepState extends State<ShimmerSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
    value: widget.phase.clamp(0.0, 1.0),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (BuildContext context, Widget? child) {
              // Kilau hanya terlihat pada sepertiga awal siklus, sisanya diam.
              final double t = (_controller.value / 0.4).clamp(0.0, 1.0);
              final double x = -1.2 + 3.4 * Curves.easeInOut.transform(t);
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(x - 0.6, -0.4),
                    end: Alignment(x + 0.6, 0.4),
                    colors: const [
                      Color(0x00FFFFFF),
                      Color(0x73FFFFFF),
                      Color(0x00FFFFFF),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
