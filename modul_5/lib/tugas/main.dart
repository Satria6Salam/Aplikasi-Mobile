import 'package:flutter/material.dart';

void main() {
  runApp(Musik());
}

class Musik extends StatelessWidget {
  Musik({super.key});

  // ignore: empty_constructor_bodies
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(title: Text('Memutar Musik'), centerTitle: true),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity, // Memaksa Card melebar dari kiri ke kanan
              child: const SongCard(),
            ),
          ),
        ),
      ),
    );
  }
}

class SongCard extends StatelessWidget {
  const SongCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1E1B24), // Warna kartu gelap sesuai gambar
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Ikon Piringan Hitam di Tengah
            const Center(
              child: Icon(
                Icons.album,
                size: 90,
                color: Color(0xFF5E7D8A), // Warna biru keabu-abuan
              ),
            ),
            const SizedBox(height: 24),

            // 2. Baris Informasi Lagu dan Tombol Suka (Heart)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Kolom Teks (Judul + Artis)
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Di sini ada judul lagu',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Di sini ada nama artis',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),

                // Ikon Hati di Sudut Kanan
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.favorite_border,
                    color: Colors.redAccent,
                  ),
                  onPressed: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
