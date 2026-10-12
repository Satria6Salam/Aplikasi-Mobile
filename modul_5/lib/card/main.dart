import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Widget: Mengatur Tampilan (UI) dan Struktur Tata Letak (Layout).
  // MaterialApp: widget pembungkus utama (root widget) yang menyalakan ekosistem Google Material Design
  // Scaffold: widget pemberi kerangka tata letak dasar untuk satu layar penuh berbasis standar Material Design.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contoh Card',
      home: Scaffold(
        appBar: AppBar(
          title: Text('Contoh SizeBox'),
          backgroundColor: Colors.amber,
        ),

        // body: const Center(child: Text('Halo Fluter')),
        body: Card(
          margin: const EdgeInsets.all(8),

          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ListTile: digunakan untuk menampilkan ikon, judul, dan teks tambahan.
              const ListTile(
                leading: Icon(Icons.location_pin, color: Colors.red),
                title: Text(
                  'Taman Nasional Bromo Tengger Semeru',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Jawa Timur, Indonesia'),
              ),
              Padding(padding: EdgeInsetsGeometry.all(5)),
              Container(
                padding: const EdgeInsets.only(left: 8, right: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // OutlinedButton memberi interaksi tambahan berupa tombol dengan ikon.
                    OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.blue),
                      ),
                      child: const Icon(Icons.map),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.blue),
                      ),
                      child: const Icon(Icons.phone),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
