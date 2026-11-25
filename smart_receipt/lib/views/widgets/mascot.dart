import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';

/// Karakter maskot SmartReceipt (berkas di assets/images).
enum MascotKind {
  /// Berjalan sambil membawa koin emas: ajakan mulai mencatat.
  coin('assets/images/mascot_coin.png', 595 / 560),

  /// Membawa karung uang, uang beterbangan: pemasukan dan tabungan.
  moneyBag('assets/images/mascot_money_bag.png', 587 / 560),

  /// Tersenyum lebar di samping karung uang: ringkasan keuangan di Beranda.
  moneyHappy('assets/images/mascot_money_happy.png', 589 / 560),

  /// Berkacamata hitam, tangan bersedekap: santai, semua terkendali.
  cool('assets/images/mascot_cool.png', 423 / 560),

  /// Jaket kulit dan jempol: sambutan di halaman Masuk.
  thumbsUp('assets/images/mascot_thumbs_up.png', 348 / 560);

  const MascotKind(this.asset, this.aspect);

  final String asset;

  /// Lebar dibanding tinggi gambar.
  final double aspect;
}

/// Menampilkan maskot dengan tinggi [height]. Bila [float] benar, maskot
/// melayang naik-turun pelan agar terasa hidup.
class Mascot extends StatefulWidget {
  const Mascot({
    super.key,
    this.kind = MascotKind.moneyHappy,
    this.height = 120,
    this.float = false,
  });

  final MascotKind kind;
  final double height;
  final bool float;

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.float) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2400),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget image = Image.asset(
      widget.kind.asset,
      height: widget.height,
      width: widget.height * widget.kind.aspect,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (BuildContext _, Object __, StackTrace? ___) => SizedBox(
        height: widget.height,
        width: widget.height * widget.kind.aspect,
        child: Icon(AppIcons.receipt,
            size: widget.height * 0.5, color: AppColors.emeraldLight),
      ),
    );
    final AnimationController? c = _controller;
    if (c == null) return image;
    return AnimatedBuilder(
      animation: c,
      builder: (BuildContext context, Widget? child) {
        final double t = Curves.easeInOut.transform(c.value);
        return Transform.translate(
          offset: Offset(0, -widget.height * 0.04 * t),
          child: child,
        );
      },
      child: image,
    );
  }
}
