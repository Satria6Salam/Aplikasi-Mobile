import 'package:flutter/material.dart';

void main() {
  runApp(MusikApp());
}

class MusikApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tampilan Musik',
      theme: ThemeData.dark(),
      home: MusikPlayApp(),
    );
  }
}

class MusikPlayApp extends StatefulWidget {
  State<MusikPlayApp> createState() => _MusikPlayAppState();
}

class _MusikPlayAppState extends State<MusikPlayApp> {
  bool _isPlaying = false;

  void _toggle() {
    setState(() {
      _isPlaying = !_isPlaying;
    });
  }

  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Play Musik'),
        centerTitle: true,
        backgroundColor: Colors.black54,
      ),

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_note, color: Colors.white, size: 150),
            Text(
              'Memutar musik ......',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w300),
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
            child: IconButton(
              iconSize: 60,
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
