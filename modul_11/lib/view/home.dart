import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../viewmodel/tasbih_controller.dart';
// ignore: unused_import
import 'package:simple_circular_progress_bar/simple_circular_progress_bar.dart';

class Home extends StatelessWidget {
  Home({super.key});

  // Inisialisasi controller GetX
  final TasbihController controller = Get.put(TasbihController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 119, 210, 145),
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Angka hitungan yang dibungkus Obx agar reaktif
              Obx(
                () => Text(
                  '${controller.counter.value.round()}',
                  style: const TextStyle(fontSize: 250),
                ),
              ),

              // Progress Bar yang dibungkus Obx agar reaktif
              Obx(
                () => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40.0),
                  child: LinearProgressIndicator(
                    // LinearProgressIndicator meminta nilai 0.0 - 1.0, jadi dibagi 100
                    value: controller.progress.value / 100,
                    backgroundColor: Colors.white54,
                    color: Colors.amberAccent.shade400,
                    minHeight: 15,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 75),

              // Tombol Fingerprint untuk menambah hitungan
              ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(50)),
                child: InkWell(
                  // Langsung memanggil method increment dari controller
                  onTap: controller.incrementCounter,
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.white),
                    padding: const EdgeInsets.all(30),
                    child: const Icon(Icons.fingerprint, size: 100),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      // Tombol melayang untuk mereset hitungan
      floatingActionButton: FloatingActionButton(
        onPressed: controller.resetCounter,
        backgroundColor: Colors.white,
        child: const Icon(Icons.refresh_outlined, color: Colors.black),
      ),
    );
  }
}
