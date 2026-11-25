import 'package:flutter/material.dart';

/// Palet warna SmartReceipt: latar putih dengan hijau samar, kartu bergradasi
/// hijau, pita hero hijau hutan, dan aksen lime pada tombol utama.
class AppColors {
  AppColors._();

  // Latar belakang & permukaan
  static const Color offWhite =
      Color(0xFFF3FAF6); // latar halaman (putih-hijau samar)
  static const Color white = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFFFFFFF); // lembar, dialog, input
  static const Color surfaceHigh = Color(0xFFFFFFFF);

  // Aksen utama: hijau hutan
  static const Color emerald = Color(0xFF16855A);
  static const Color emeraldDark = Color(0xFF0F6B47); // hover / pressed
  static const Color emeraldDeep = Color(0xFF0B5238); // teks pada lencana hijau
  static const Color forest = Color(0xFF083D2A); // judul gelap & kartu gelap
  static const Color emeraldLight = Color(0xFF34C38A); // sorotan grafik
  static const Color mint = Color(0xFFDDF3E8); // latar ikon lembut
  static const Color emeraldTint = Color(0x1A16855A); // hijau transparan 10%

  // Aksen lime untuk tombol utama dan penanda terpilih di atas latar gelap.
  static const Color lime = Color(0xFFC6F432);
  static const Color limeDeep = Color(0xFF8FD621);

  // Teks & tipografi
  static const Color slateDark = Color(0xFF0F172A); // judul utama
  static const Color coolGray = Color(0xFF64748B); // subjudul, label

  // Warna semantik
  static const Color error = Color(0xFFEF4444);
  static const Color errorTint = Color(0x1AEF4444);

  static const Color warning = Color(0xFFF59E0B);
  static const Color warningTint = Color(0x1FF59E0B);
  static const Color warningDeep = Color(0xFFB45309);

  // Garis tipis & bayangan
  static const Color border = Color(0xFFE2E8F0);
  static const Color shadow = Color(0x330B5238); // hijau gelap ~20%

  // Permukaan kaca di atas latar hijau gelap.
  static const Color glassFill = Color(0x26FFFFFF);
  static const Color glassBorder = Color(0x40FFFFFF);
  static const Color heroTop = Color(0xFF0D5C3F);
  static const Color heroBottom = Color(0xFF062B1E);

  /// Latar kepala Beranda dan halaman masuk: hijau hutan bergradasi.
  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF14855A), heroTop, heroBottom],
    stops: [0, 0.55, 1],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1E9A68), Color(0xFF0F6B47)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Gradien kartu utama (saldo/pengeluaran) seperti kartu bank.
  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1A8A5C), Color(0xFF0B5238), Color(0xFF083D2A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
