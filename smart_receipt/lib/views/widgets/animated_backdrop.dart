import 'package:flutter/material.dart';

import 'app_background.dart';

/// Dipertahankan agar pemanggil lama tetap berfungsi; kini sama dengan
/// [AppBackground] supaya latar seragam di semua halaman.
class AnimatedBackdrop extends StatelessWidget {
  const AnimatedBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AppBackground(child: child);
}
