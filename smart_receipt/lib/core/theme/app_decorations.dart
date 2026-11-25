import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Radius sudut dinamis sesuai panduan desain.
class AppRadius {
  AppRadius._();

  static const double cardLarge = 24; // kartu besar (dasbor utama)
  static const double card = 16; // kartu standar
  static const double control = 12; // input field & tombol aksi
}

/// Jarak antar komponen (ruang putih ekstra, minimal 16-24px).
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Dekorasi siap pakai: kartu putih dengan bayangan lembut (soft depth).
class AppDecorations {
  AppDecorations._();

  /// Bayangan hijau lembut: kartu tampak melayang di atas latar terang.
  static const List<BoxShadow> softShadow = [
    BoxShadow(
      color: Color(0x290B5238),
      blurRadius: 22,
      offset: Offset(0, 8),
    ),
  ];

  /// Gradasi kartu: putih kehijauan di kiri atas menuju hijau mint di kanan bawah.
  static const LinearGradient cardFill = LinearGradient(
    colors: [Color(0xFFF7FDFA), Color(0xFFCDECDB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Kartu kaca: isi putih tembus pandang dengan garis tepi tipis.
  /// Dipakai di atas latar hijau gelap.
  static BoxDecoration glass({double radius = AppRadius.card}) {
    return BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0x33FFFFFF), Color(0x14FFFFFF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: AppColors.glassBorder),
    );
  }

  static BoxDecoration card({double radius = AppRadius.card}) {
    // Gradasi hijau mint dengan tepi putih berkilau, bukan kotak putih polos.
    return BoxDecoration(
      gradient: cardFill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: const Color(0xFFFFFFFF), width: 1.5),
      boxShadow: softShadow,
    );
  }
}
