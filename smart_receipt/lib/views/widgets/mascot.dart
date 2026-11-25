import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';

/// Karakter maskot SmartReceipt (berkas di assets/images).
enum MascotKind {
  /// Struk yang mengedip dan mengacungkan jari.
  receipt('assets/images/mascot_receipt.png', 302 / 274),

  /// Mesin EDC dengan isyarat "oke".
  edcOk('assets/images/mascot_edc_ok.png', 445 / 480),

  /// Mesin EDC berkacamata hitam sambil membawa es krim.
  edcCool('assets/images/mascot_edc_cool.png', 480 / 428);

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
    this.kind = MascotKind.receipt,
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
