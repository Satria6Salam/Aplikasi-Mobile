import 'package:flutter/material.dart';

void main() {
  // Method runApp() digunakan untuk menjalankan aplikasi Flutter.
  runApp(const MyApp());
}

// Kelas MyApp adalah kelas utama dari aplikasi Flutter.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Method build() digunakan untuk membangun tampilan aplikasi.
  // MaterialApp adalah widget yang digunakan untuk membuat aplikasi berbasis Material Design.
  // Scaffold adalah widget yang digunakan untuk membuat AppBar dan Body.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Row dan Column',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Row dan Column'),
          backgroundColor: Colors.yellow,
        ),

        body: Center(child: KotakBiruJempol()),
      ),
    );
  }
}

// KotakBiruJempol adalah widget kustom yang menampilkan kotak biru dengan ikon jempol di dalamnya.
class KotakBiruJempol extends StatelessWidget {
  const KotakBiruJempol({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.blue,
        borderRadius: BorderRadius.circular(12),
      ),

      child: Icon(Icons.thumb_up, color: Colors.white, size: 40),
    );
  }
}
