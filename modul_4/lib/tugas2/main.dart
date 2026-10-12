import 'package:flutter/material.dart';

void main() {
  runApp(const MusikApp());
}

// Class MusikApp: kerangka dasar untuk mengatur theme, nama aplikasi dan memanggil class MusikPlayerApp()
class MusikApp extends StatelessWidget {
  const MusikApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Musik',
      theme: ThemeData.dark(),
      home: MusikPlayerApp(),
    );
  }
}

// class MusikPlayerApp: halaman utama musik untuk komponen" yang akan dibuat
class MusikPlayerApp extends StatefulWidget {
  const MusikPlayerApp({super.key});

  @override
  State<MusikPlayerApp> createState() {
    return _MusikPlayerAppState();
  }
}

// class _MusikPlayerAppState: Mengelola data dibalik layar
// menyimpan data putar, pengubah status musik on / off,
class _MusikPlayerAppState extends State<MusikPlayerApp> {
  bool _isPlaying = false;

  void _toggle() {
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pemutar Musik'), centerTitle: true),

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note, color: Colors.white38, size: 100),
            SizedBox(height: 12),
            Text(
              'Memutar musik....',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: MusikKontrol(
        isPlaying: _isPlaying,
        onPlayPres: _toggle,
      ),
    );
  }
}

class MusikKontrol extends StatelessWidget {
  final bool isPlaying;
  final VoidCallback onPlayPres;

  MusikKontrol({super.key, required this.isPlaying, required this.onPlayPres});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      color: Colors.black26,
      child: Row(
        children: [
          Expanded(
            child: IconButton(
              icon: Icon(Icons.shuffle, color: Colors.white),
              onPressed: () {},
            ),
          ),

          Expanded(
            child: IconButton(
              icon: Icon(Icons.skip_previous, color: Colors.white),
              onPressed: () {},
            ),
          ),

          Flexible(
            flex: 2,
            fit: FlexFit.tight,
            child: IconButton(
              iconSize: 40,
              icon: Icon(
                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              ),
              onPressed: onPlayPres,
            ),
          ),

          Expanded(
            child: IconButton(
              icon: Icon(Icons.skip_next, color: Colors.white),
              onPressed: () {},
            ),
          ),

          Expanded(
            child: IconButton(
              icon: Icon(Icons.repeat, color: Colors.white),
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }
}
