import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flexible',
      // ThemeData(...): menyimpan aturan gaya antarmuka, seperti skema warna, gaya teks, hingga bentuk tombol.
      // primarySwatch: Parameter untuk menentukan palet warna sampel utama (color swatch).
      theme: ThemeData(primarySwatch: Colors.blue),
      home: Scaffold(
        appBar: AppBar(title: Text('Flexible')),

        body: Center(
          child: Row(
            // Flexible: Widget pembungkus yang memberi tahu Flutter untuk membagi sisa ruang layar secara responsif agar antarmuka tidak mengalami overflow (layar jebol/garis kuning-hitam).
            // flex: Parameter rasio atau perbandingan pembagian ruang.
            // fit: FlexFit.tight memaksa KotakBiruJempolKecil() untuk membesar hingga memenuhi 100%
            // fit: FlexFit.loose Memperbolehkan widget di dalamnya (KotakBiruJempolKecil()) memiliki ukuran yang lebih kecil dari jatah ruang yang dialokasikan.
            children: [
              // Flexible(flex: 4, child: KotakBiruJempolKecil()),
              // Flexible(flex: 5, child: KotakBiruJempolKecil()),
              // Flexible(flex: 4, child: KotakBiruJempolKecil()),
              Flexible(
                fit: FlexFit.tight,
                flex: 2,
                child: KotakBiruJempolKecil(),
              ),
              Flexible(
                fit: FlexFit.tight,
                flex: 3,
                child: KotakBiruJempolKecil(),
              ),
              Flexible(
                fit: FlexFit.loose,
                flex:
                    2, // Widget tidak akan pernah melebihi batas 2 bagian ini, meskipun konten di dalamnya sangat panjang.
                child: KotakBiruJempolKecil(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class KotakBiruJempolKecil extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 75,
      height: 75,
      // BoxDecoration: digunakan untuk mendesain tampilan visual wadah (seperti Container atau DecoratedBox).
      // color, borderRadius, border, boxShadow, gradient, shape, image.
      decoration: BoxDecoration(
        color: Colors.blue,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Icon(Icons.thumb_up, color: Colors.white, size: 40),
    );
  }
}
