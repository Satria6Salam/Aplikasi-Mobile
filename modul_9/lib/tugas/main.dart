import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simple_circular_progress_bar/simple_circular_progress_bar.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // _valueNotifier digunakan untuk mengontrol pergerakan circular progress.
  late ValueNotifier<double> _valueNotifier;
  // counter menyimpan nilai hitungan tasbih maksimal hingga 33.
  late double counter;

  @override
  void initState() {
    super.initState();
    _valueNotifier = ValueNotifier(0.0);
    counter = 0.0;
  }

  @override
  void dispose() {
    _valueNotifier.dispose();
    super.dispose();
  }

  // Fungsi untuk menambah nilai counter hingga batas maksimal 33.
  void incrementCounter() {
    setState(() {
      if (counter < 33) {
        counter++;
        // Menyesuaikan persentase lingkaran berdasarkan rasio 100%
        _valueNotifier.value = (counter / 33) * 100;
      }
    });
  }

  // Fungsi untuk mengembalikan hitungan tasbih dan progres lingkaran ke 0.
  void resetCounter() {
    setState(() {
      counter = 0.0;
      _valueNotifier.value = (counter / 33) * 100;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Membuat tampilan status bar menjadi transparan
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 119, 210, 145),
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        backgroundColor: const Color.fromARGB(255, 119, 210, 145),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Menampilkan angka hitungan di atas circular progress
                Text(
                  '${(counter.round())}',
                  style: const TextStyle(fontSize: 50),
                ),
                // Widget dari simple_circular_progress_bar
                SimpleCircularProgressBar(
                  progressColors: [Colors.amberAccent.shade400],
                  size: 300,
                  progressStrokeWidth: 20,
                  backStrokeWidth: 10,
                  mergeMode: true,
                  maxValue: 100,
                  animationDuration: 0,
                  valueNotifier: _valueNotifier,
                  onGetText: (value) {
                    return Text(
                      '${(value.toInt() / 3).round()}',
                      style: const TextStyle(fontSize: 170),
                    );
                  },
                ),
                const SizedBox(height: 50),
                // Tombol Sidik Jari untuk menambah hitungan (InkWell dibungkus ClipRRect)
                ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(50)),
                  child: InkWell(
                    onTap: incrementCounter,
                    child: Container(
                      decoration: const BoxDecoration(color: Colors.white),
                      child: const Icon(Icons.fingerprint, size: 125),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Tombol melayang (Floating Action Button) untuk mereset hitungan
        floatingActionButton: FloatingActionButton(
          onPressed: resetCounter,
          child: const Icon(Icons.refresh_outlined),
        ),
      ),
    );
  }
}
