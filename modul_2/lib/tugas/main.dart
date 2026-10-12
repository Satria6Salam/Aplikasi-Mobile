import 'package:flutter/material.dart';

void main() {
  // Method runApp() digunakan untuk menjalankan aplikasi Flutter.
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Row dan Column',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Grid 2x2 Favorites'),
          backgroundColor: Colors.yellow,
        ),

        // Center digunakan untuk memusatkan widget di tengah layar.
        body: Center(
          // Menggunakan Column untuk menampilkan dua baris kotak warna favorit
          // MainAxisAlignment: untuk memusatkan baris secara vertikal di tengah layar.
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                // MainAxisAlignment: untuk memusatkan kotak warna favorit di tengah baris.
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  KotakWarnaFavorit(warnaKotak: Colors.orange, label: 'Orange'),
                  const SizedBox(width: 20),
                  KotakWarnaFavorit(warnaKotak: Colors.black, label: 'Hitam'),
                ],
              ),

              const SizedBox(height: 20), // Jarak vertikal antar baris

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  KotakWarnaFavorit(warnaKotak: Colors.yellow, label: 'Kuning'),
                  const SizedBox(width: 20),
                  KotakWarnaFavorit(warnaKotak: Colors.green, label: 'Hijau'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KotakWarnaFavorit extends StatelessWidget {
  final Color warnaKotak;
  final String label;

  // super.key digunakan untuk mengirimkan key ke widget induk.
  // key: digunakan untuk mengidentifikasi widget secara unik dalam widget tree.
  const KotakWarnaFavorit({
    super.key,
    required this.warnaKotak,
    required this.label,
  });

  // build() method digunakan untuk membangun tampilan kotak warna favorit.
  // Container: digunakan untuk membuat kotak warna favorit dengan ukuran 100x100 piksel.
  // BoxDecoration: digunakan untuk memberikan dekorasi pada kotak
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: warnaKotak,
        borderRadius: BorderRadius.circular(12),
      ),

      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite, color: Colors.red, size: 50),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
