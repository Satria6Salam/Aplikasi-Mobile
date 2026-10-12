import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expanded',
      home: Scaffold(
        appBar: AppBar(title: Text('Expanded')),
        body: Column(
          children: [
            _kotakUji(Colors.red, 150, 'Normal'),
            Flexible(
              fit: FlexFit.tight,
              flex: 2,
              child: _kotakUji(Colors.blue, 100, 'Flexible'),
            ),
            // Expanded:
            Expanded(flex: 2, child: _kotakUji(Colors.green, 250, 'Expanded')),
          ],
        ),
      ),
    );
  }

  Container _kotakUji(Color warna, double tinggi, String teks) {
    return Container(
      // double.infinity:
      width: double.infinity,
      height: tinggi,
      color: warna,
      alignment: const Alignment(0.0, 0.0),
      child: Text(
        teks,
        style: const TextStyle(color: Colors.white, fontSize: 30),
      ),
    );
  }
}
