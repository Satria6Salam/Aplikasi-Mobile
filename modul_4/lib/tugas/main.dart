import 'package:flutter/material.dart';

void main() {
  runApp(const MusikPlayerApp());
}

// Kerangka dasar aplikasi secara keseluruhan
// judul apk, tema,
class MusikPlayerApp extends StatelessWidget {
  const MusikPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pemutar Musik',
      debugShowCheckedModeBanner: false,
      // Spesifikasi a: Theme aplikasi gelap (ThemeData.dark)
      theme: ThemeData.dark(),
      home: const MusikPlayerPage(),
    );
  }
}

// Halaman utama tampilan pemutar musik
class MusikPlayerPage extends StatefulWidget {
  const MusikPlayerPage({super.key});

  // State: Pengelola data / status
  @override
  State<MusikPlayerPage> createState() => _MusikPlayerPageState();
}

// Pengelola data dibalik layar
// menyimpan data putar, pengubah status musik
class _MusikPlayerPageState extends State<MusikPlayerPage> {
  bool _isPlaying = false;

  void _togglePlayMouse() {
    // setState: mengubah data play / pause
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seni Musik'), centerTitle: true),

      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note, size: 100, color: Colors.white38),
            SizedBox(height: 16),
            Text(
              'Memutar Musik...',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),

      bottomNavigationBar: MusikKontrolBar(
        isPlaying: _isPlaying,
        onPlayPressed: _togglePlayMouse,
      ),
    );
  }
}

// Mengatur tampilan toolbar atau kontrol musik dibagian bawah layar
class MusikKontrolBar extends StatelessWidget {
  final bool isPlaying;
  // tipe data khusus mewakili fungsi yang tidak memiliki parameter
  final VoidCallback onPlayPressed;

  const MusikKontrolBar({
    super.key,
    required this.isPlaying,
    required this.onPlayPressed,
  });

  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      color: Colors.black54,
      child: Row(
        children: [
          // shuffle
          Expanded(
            child: IconButton(
              icon: const Icon(Icons.shuffle, color: Colors.white),
              onPressed: () {},
            ),
          ),

          // previous
          Expanded(
            child: IconButton(
              icon: const Icon(Icons.skip_previous, color: Colors.white),
              onPressed: () {},
            ),
          ),

          // play
          Flexible(
            flex: 2,
            fit: FlexFit.tight,
            child: IconButton(
              iconSize: 40,
              icon: Icon(
                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              ),
              onPressed: onPlayPressed,
            ),
          ),

          // Next
          Expanded(
            child: IconButton(
              icon: const Icon(Icons.skip_next, color: Colors.white),
              onPressed: () {},
            ),
          ),

          Expanded(
            child: IconButton(
              icon: const Icon(
                Icons.repeat,
                color: Colors.white,
              ), // Spesifikasi g
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }
}
