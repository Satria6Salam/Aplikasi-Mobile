import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'mascot.dart';

/// Kepala halaman Masuk dan Daftar: panel hijau bergradasi dengan satu maskot.
///
/// Saat halaman dibuka, maskot melompat naik dari bawah, lalu kartu kaca berisi
/// sapaan meluncur masuk di sampingnya dengan bilah kemajuan yang terisi.
/// Setelah itu maskot melayang pelan.
class AuthHero extends StatefulWidget {
  const AuthHero({
    super.key,
    this.height = 300,
    this.mascot = MascotKind.thumbsUp,
    this.title = 'Halo!',
    this.subtitle = 'Yuk lanjut catat keuanganmu',
    this.topInset = 0,
  });

  final double height;
  final MascotKind mascot;
  final String title;
  final String subtitle;

  /// Ruang di atas (mis. bilah status) yang tidak boleh ditempati isi.
  final double topInset;

  @override
  State<AuthHero> createState() => _AuthHeroState();
}

class _AuthHeroState extends State<AuthHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..forward();

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  /// Bagian animasi pada rentang [begin]..[end] dari durasi total.
  Animation<double> _part(double begin, double end, Curve curve) =>
      CurvedAnimation(
        parent: _enter,
        curve: Interval(begin, end, curve: curve),
      );

  @override
  Widget build(BuildContext context) {
    final double contentHeight = widget.height - widget.topInset;
    final double mascotHeight = (contentHeight * 0.82).clamp(120.0, 250.0);
    final Animation<double> rise = _part(0, 0.55, Curves.easeOutBack);
    final Animation<double> fade = _part(0, 0.3, Curves.easeOut);
    final Animation<double> card = _part(0.35, 0.8, Curves.easeOutCubic);
    final Animation<double> fill = _part(0.6, 1, Curves.easeInOutCubic);

    return Container(
      height: widget.height,
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
            right: 16,
            bottom: 14,
            child: AnimatedBuilder(
              animation: _enter,
              builder: (BuildContext context, Widget? child) {
                final double t = rise.value;
                return Opacity(
                  opacity: fade.value,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * mascotHeight * 0.6),
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * t,
                      alignment: Alignment.bottomCenter,
                      child: child,
                    ),
                  ),
                );
              },
              child: Mascot(
                kind: widget.mascot,
                height: mascotHeight,
                float: true,
              ),
            ),
          ),
          // Kartu sapaan meluncur dari kiri bersamaan dengan maskot.
          Positioned(
            left: 20,
            bottom: 28,
            child: AnimatedBuilder(
              animation: _enter,
              builder: (BuildContext context, Widget? child) {
                return Opacity(
                  opacity: card.value,
                  child: Transform.translate(
                    offset: Offset(-40 * (1 - card.value), 0),
                    child: Transform.rotate(
                      angle: -0.05 * (1 - card.value),
                      child: child,
                    ),
                  ),
                );
              },
              child: _GreetingCard(
                title: widget.title,
                subtitle: widget.subtitle,
                fill: fill,
              ),
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

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({
    required this.title,
    required this.subtitle,
    required this.fill,
  });

  final String title;
  final String subtitle;
  final Animation<double> fill;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      width: 168,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x40FFFFFF), Color(0x1AFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: textTheme.titleLarge?.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:
                textTheme.bodySmall?.copyWith(color: const Color(0xD9FFFFFF)),
          ),
          const SizedBox(height: 10),
          // Bilah kemajuan yang terisi: kesan "keuangan makin rapi".
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 6,
              child: Stack(
                children: [
                  Container(color: const Color(0x33FFFFFF)),
                  AnimatedBuilder(
                    animation: fill,
                    builder: (BuildContext context, Widget? child) =>
                        FractionallySizedBox(
                      widthFactor: 0.72 * fill.value,
                      child: child,
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.lime, AppColors.limeDeep],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
