import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const LokasiApp());
}

class LokasiApp extends StatelessWidget {
  const LokasiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lokasi Saya',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A237E)),
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: const HalamanLokasi(),
    );
  }
}

class HalamanLokasi extends StatefulWidget {
  const HalamanLokasi({super.key});

  @override
  State<HalamanLokasi> createState() => _HalamanLokasiState();
}

class _HalamanLokasiState extends State<HalamanLokasi> {
  bool sedangMemuat = false;

  String alamat = 'Belum ada data lokasi';
  String latitude = '-';
  String longitude = '-';
  String pesan = 'Tekan tombol di bawah untuk mengambil lokasi.';
  bool lokasiDitemukan = false;

  Future<void> tampilkanLokasi() async {
    setState(() {
      sedangMemuat = true;
      pesan = 'Sedang mengambil lokasi...';
    });

    try {
      // 1. Periksa apakah layanan lokasi aktif.
      bool layananAktif = await Geolocator.isLocationServiceEnabled();

      if (!layananAktif) {
        throw Exception('GPS belum aktif. Aktifkan layanan lokasi di HP.');
      }

      // 2. Periksa izin lokasi.
      LocationPermission izin = await Geolocator.checkPermission();

      if (izin == LocationPermission.denied) {
        izin = await Geolocator.requestPermission();
      }

      if (izin == LocationPermission.denied) {
        throw Exception('Izin lokasi ditolak.');
      }

      if (izin == LocationPermission.deniedForever) {
        throw Exception(
          'Izin lokasi ditolak permanen. '
          'Aktifkan melalui Pengaturan Aplikasi.',
        );
      }

      // 3. Ambil koordinat GPS.
      Position posisi = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 30),
        ),
      );

      String hasilAlamat = 'Alamat tidak tersedia';

      // 4. Ubah koordinat menjadi informasi alamat.
      try {
        List<Placemark> daftarAlamat = await placemarkFromCoordinates(
          posisi.latitude,
          posisi.longitude,
        );

        if (daftarAlamat.isNotEmpty) {
          Placemark tempat = daftarAlamat.first;

          final bagianAlamat = [
            tempat.street,
            tempat.subLocality,
            tempat.locality,
            tempat.subAdministrativeArea,
            tempat.administrativeArea,
            tempat.postalCode,
            tempat.country,
          ].where((bagian) => bagian != null && bagian.trim().isNotEmpty);

          if (bagianAlamat.isNotEmpty) {
            hasilAlamat = bagianAlamat.join(', ');
          }
        }
      } catch (_) {
        hasilAlamat =
            'Alamat tidak dapat diperoleh. '
            'Periksa koneksi internet.';
      }

      if (!mounted) return;

      setState(() {
        latitude = posisi.latitude.toStringAsFixed(6);
        longitude = posisi.longitude.toStringAsFixed(6);
        alamat = hasilAlamat;
        pesan = 'Lokasi berhasil ditemukan.';
        lokasiDitemukan = true;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        pesan = e.toString().replaceFirst('Exception: ', '');
        lokasiDitemukan = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(pesan), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) {
        setState(() {
          sedangMemuat = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const warnaUtama = Color(0xFF1A237E);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: warnaUtama,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text(
          'Lokasi Saya',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 18),

              // Ikon utama aplikasi.
              Container(
                height: 130,
                width: 130,
                decoration: BoxDecoration(
                  color: warnaUtama.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 76,
                  color: warnaUtama,
                ),
              ),

              const SizedBox(height: 22),

              const Text(
                'Lokasi GPS Saat Ini',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF20264D),
                ),
              ),

              const SizedBox(height: 8),

              Text(
                pesan,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),

              const SizedBox(height: 26),

              // Kartu informasi lokasi.
              Card(
                elevation: 2,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.my_location, color: warnaUtama),
                          SizedBox(width: 10),
                          Text(
                            'Informasi Lokasi',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const Divider(height: 28),

                      const Text(
                        'Alamat / Wilayah',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        alamat,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),

                      const SizedBox(height: 22),

                      const Text(
                        'Latitude',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                      const SizedBox(height: 5),
                      SelectableText(
                        latitude,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        'Longitude',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                      const SizedBox(height: 5),
                      SelectableText(
                        longitude,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Tombol untuk mengambil lokasi.
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: sedangMemuat ? null : tampilkanLokasi,
                  icon: sedangMemuat
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.gps_fixed),
                  label: Text(
                    sedangMemuat
                        ? 'MENCARI LOKASI...'
                        : 'TAMPILKAN LOKASI SAAT INI',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: warnaUtama,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: warnaUtama.withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              if (lokasiDitemukan)
                const Text(
                  'Koordinat menunjukkan posisi yang '
                  'dilaporkan oleh perangkat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.black45),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
