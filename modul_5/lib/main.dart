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
      title: 'Contoh SizeBox',
      home: Scaffold(
        appBar: AppBar(
          title: Text('Contoh SizeBox'),
          backgroundColor: Colors.amber,
        ),

        // body: const Center(child: Text('Halo Fluter')),
        body: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Spacer: untuk memberikan jarak antar widget dengan nilai flex,
              kotakUji(Colors.amber),
              SizedBox(width: 25, height: 25),
              // const Spacer(flex: 1),
              kotakUji(Colors.green),
              SizedBox(width: 25, height: 25, child: kotakUji(Colors.green)),
              // const Spacer(flex: 1),
              kotakUji(Colors.blue),
            ],
          ),
        ),
      ),
    );
  }

  Container kotakUji(Color warna) {
    return Container(height: 75, width: 75, color: warna);
  }
}
