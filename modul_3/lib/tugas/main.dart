import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: Text(
            'Informasi Suhu Harian',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              fontStyle: FontStyle.italic,
            ),
          ),
          backgroundColor: Colors.blue,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(
                'Malang',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
              ),
              Text('25\u00B0C', style: TextStyle(fontSize: 100)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Cuaca(hari: 'Rabu', icon: Icons.sunny, suhu: 12),
                  Cuaca(hari: 'Kamis', icon: Icons.cloudy_snowing, suhu: 10),
                  Cuaca(hari: 'Jumat', icon: Icons.cloud, suhu: 14),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class Cuaca extends StatelessWidget {
  final String hari;
  final IconData icon;
  final int suhu;

  const Cuaca({
    super.key,
    required this.hari,
    required this.icon,
    required this.suhu,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 150,
      decoration: BoxDecoration(
        color: Colors.blue,
        // border: Border.all(color: Colors.black, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,

        children: [
          Text(
            hari,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              fontFamily: 'Arial',
              color: Colors.black,
            ),
          ),
          Icon(icon, size: 40, color: Colors.black),
          Text(
            '$suhu\u00B0C',
            style: TextStyle(fontSize: 15, color: Colors.black),
          ),
        ],
      ),
    );
  }
}
