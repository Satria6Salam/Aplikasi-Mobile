import 'package:get/get.dart';

class TasbihController extends GetxController {
  // Deklarasi variabel reaktif menggunakan .obs
  var counter = 0.0.obs;
  var progress = 0.0.obs;
  final double maxCount = 33; // Batas maksimal hitungan tasbih

  // Method untuk menambah hitungan
  void incrementCounter() {
    if (counter.value < maxCount) {
      counter.value++;
      // Menghitung persentase progress (0 - 100)
      progress.value = (counter.value / maxCount) * 100;
    }
  }

  // Method untuk mereset hitungan
  void resetCounter() {
    counter.value = 0;
    progress.value = 0;
  }
}
