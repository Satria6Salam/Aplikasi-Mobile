import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alignment',
      theme: ThemeData(primarySwatch: Colors.blue),

      home: Scaffold(
        appBar: AppBar(title: const Text('Alignment')),
        body: Center(
          child: Column(
            /*
                1. start: Menempatkan widget di awal sumbu utama (atas untuk Column, kiri untuk Row).
                2. end: Menempatkan widget di akhir sumbu utama (bawah untuk Column, kanan untuk Row).
                3. center: Menempatkan widget di tengah sumbu utama. 
                4. spaceBetween: Menempatkan widget dengan jarak yang sama di antara mereka, tanpa jarak di awal dan akhir.
                5. spaceAround: Menempatkan widget dengan jarak yang sama di antara mereka, dengan jarak setengah di awal dan akhir.
                6. spaceEvenly: Menempatkan widget dengan jarak yang sama di antara mereka, termasuk di awal dan akhir.
            */
            mainAxisAlignment: MainAxisAlignment
                .spaceEvenly, // mainAxisAlignment: digunakan untuk mengatur posisi widget di sepanjang sumbu utama (horizontal untuk Row, vertikal untuk Column). MainAxisAlignment.start akan menempatkan widget di awal sumbu utama,
            crossAxisAlignment: CrossAxisAlignment
                .center, // crossAxisAlignment: digunakan untuk mengatur posisi widget di sepanjang sumbu silang (vertikal untuk Row, horizontal untuk Column). CrossAxisAlignment.start akan menempatkan widget di awal sumbu silang,
            textBaseline: TextBaseline
                .alphabetic, // textBaseline: digunakan untuk mengatur garis dasar teks dalam widget. TextBaseline.alphabetic akan menyelaraskan teks berdasarkan garis dasar alfabetik,
            // mainAxisSize: digunakan untuk mengatur ukuran utama dari Row atau Column. MainAxisSize.max akan membuat Row atau Column mengambil seluruh ruang yang tersedia di sepanjang sumbu utama,
            // MainAxisSize.min akan membuat Row atau Column hanya sebesar kontennya.
            // mainAxisSize: MainAxisSize.min,
            children: [
              Text('Suhu:', style: TextStyle(fontSize: 30)),
              Text('25\u00B0C', style: TextStyle(fontSize: 78)),
              Icon(Icons.sunny, color: Colors.amber, size: 45),
              // KotakBiruJempolKecil(),
              // SizedBox(width: 20),
              // KotakBiruJempol(),
              // SizedBox(width: 20),
              // KotakBiruJempolKecil(),
            ],
          ),
        ),
      ),
    );
  }
}

class KotakBiruJempol extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.blue,
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),

      child: Icon(Icons.thumb_up, color: Colors.white, size: 50),
    );
  }
}

class KotakBiruJempolKecil extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 75,
      height: 75,
      decoration: BoxDecoration(
        color: Colors.blue,
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),

      child: Icon(Icons.thumb_up, color: Colors.white, size: 40),
    );
  }
}
