/// Memetakan MCC (Merchant Category Code, 4 digit pada QRIS) ke nama kategori
/// aplikasi. Nama harus sama persis dengan tabel `categories`.
///
/// MCC menggambarkan JENIS usaha, jadi hasilnya perkiraan awal yang tetap
/// bisa diubah pengguna. MCC yang tidak dikenal menjadi "Lainnya".
class MccCategories {
  MccCategories._();

  static const String fallback = 'Lainnya';

  /// Kategori untuk [mcc]; [fallback] bila tidak dikenal atau tidak valid.
  static String of(String? mcc) {
    final int? code = int.tryParse((mcc ?? '').trim());
    if (code == null) return fallback;

    final String? exact = _exact[code];
    if (exact != null) return exact;
    for (final _Range r in _ranges) {
      if (code >= r.from && code <= r.to) return r.category;
    }
    return fallback;
  }

  /// Penjelasan singkat jenis usaha untuk ditampilkan, mis. "Restoran".
  static String? label(String? mcc) =>
      _labels[int.tryParse((mcc ?? '').trim())];

  static const Map<int, String> _exact = <int, String>{
    // Makanan & minuman siap santap.
    5811: 'Konsumsi', // Katering
    5812: 'Konsumsi', // Restoran
    5813: 'Konsumsi', // Bar / kedai minuman
    5814: 'Konsumsi', // Makanan cepat saji
    5462: 'Konsumsi', // Toko roti
    5441: 'Konsumsi', // Permen dan camilan
    5499: 'Konsumsi', // Toko makanan lain / minimarket
    // Bahan makanan.
    5411: 'Bahan Makanan', // Swalayan / supermarket
    5422: 'Bahan Makanan', // Daging beku
    5451: 'Bahan Makanan', // Produk susu
    5300: 'Bahan Makanan', // Klub grosir
    5921: 'Bahan Makanan', // Toko minuman
    // Transportasi.
    4111: 'Transportasi', 4112: 'Transportasi', 4121: 'Transportasi',
    4131: 'Transportasi', 4784: 'Transportasi', 5541: 'Transportasi',
    5542: 'Transportasi', 7523: 'Transportasi', 7512: 'Transportasi',
    7538: 'Transportasi', 5511: 'Transportasi', 5531: 'Transportasi',
    5533: 'Transportasi', 4011: 'Transportasi', 4511: 'Transportasi',
    4411: 'Transportasi',
    // Kesehatan.
    5912: 'Kesehatan', 5122: 'Kesehatan', 8062: 'Kesehatan',
    8071: 'Kesehatan', 8099: 'Kesehatan', 5975: 'Kesehatan',
    5976: 'Kesehatan',
    // Perawatan diri.
    7230: 'Perawatan Diri', 7298: 'Perawatan Diri', 7297: 'Perawatan Diri',
    5977: 'Perawatan Diri', 7991: 'Hiburan',
    // Elektronik.
    5732: 'Elektronik', 5734: 'Elektronik', 5045: 'Elektronik',
    5946: 'Elektronik', 7622: 'Elektronik', 5065: 'Elektronik',
    // Rumah tangga.
    5200: 'Rumah Tangga', 5211: 'Rumah Tangga', 5712: 'Rumah Tangga',
    5714: 'Rumah Tangga', 5719: 'Rumah Tangga', 5722: 'Rumah Tangga',
    5713: 'Rumah Tangga', 5718: 'Rumah Tangga', 5231: 'Rumah Tangga',
    5251: 'Rumah Tangga', 5261: 'Rumah Tangga',
    // Pakaian & aksesori.
    5651: 'Pakaian & Aksesori', 5661: 'Pakaian & Aksesori',
    5944: 'Pakaian & Aksesori', 5948: 'Pakaian & Aksesori',
    5655: 'Pakaian & Aksesori', 5691: 'Pakaian & Aksesori',
    5699: 'Pakaian & Aksesori', 5621: 'Pakaian & Aksesori',
    5631: 'Pakaian & Aksesori', 5641: 'Pakaian & Aksesori',
    // Pendidikan.
    5942: 'Pendidikan', 5943: 'Pendidikan', 5111: 'Pendidikan',
    // Hiburan.
    7832: 'Hiburan', 7841: 'Hiburan', 7922: 'Hiburan', 7996: 'Hiburan',
    7941: 'Hiburan', 7992: 'Hiburan', 7993: 'Hiburan', 7994: 'Hiburan',
    7995: 'Hiburan', 5815: 'Hiburan', 5816: 'Hiburan', 5817: 'Hiburan',
    5818: 'Hiburan', 5735: 'Hiburan', 7929: 'Hiburan', 7932: 'Hiburan',
    // Tagihan & utilitas.
    4900: 'Tagihan & Utilitas', 4814: 'Tagihan & Utilitas',
    4899: 'Tagihan & Utilitas', 4812: 'Tagihan & Utilitas',
    4816: 'Tagihan & Utilitas', 6513: 'Tagihan & Utilitas',
    6012: 'Tagihan & Utilitas', 6300: 'Tagihan & Utilitas',
    9311: 'Tagihan & Utilitas', 9399: 'Tagihan & Utilitas',
    // Jasa & layanan.
    7210: 'Jasa & Layanan', 7216: 'Jasa & Layanan', 7217: 'Jasa & Layanan',
    7349: 'Jasa & Layanan', 7399: 'Jasa & Layanan', 4215: 'Jasa & Layanan',
    7311: 'Jasa & Layanan', 7392: 'Jasa & Layanan', 7394: 'Jasa & Layanan',
    7531: 'Jasa & Layanan', 7534: 'Jasa & Layanan', 7535: 'Jasa & Layanan',
    7542: 'Jasa & Layanan', 7699: 'Jasa & Layanan', 7221: 'Jasa & Layanan',
    7251: 'Jasa & Layanan', 7261: 'Jasa & Layanan', 7276: 'Jasa & Layanan',
    // Donasi & sosial.
    8398: 'Donasi & Sosial', 8661: 'Donasi & Sosial', 8641: 'Donasi & Sosial',
    8651: 'Donasi & Sosial', 5947: 'Donasi & Sosial',
    // Belanja umum.
    5311: 'Belanja', 5310: 'Belanja', 5331: 'Belanja', 5399: 'Belanja',
    5999: 'Belanja', 5964: 'Belanja', 5965: 'Belanja', 5969: 'Belanja',
    5992: 'Belanja', 5993: 'Belanja', 5994: 'Belanja', 5995: 'Belanja',
    5945: 'Belanja', 5970: 'Belanja', 5971: 'Belanja', 5972: 'Belanja',
    5973: 'Belanja', 5978: 'Belanja', 5983: 'Belanja',
  };

  static const List<_Range> _ranges = <_Range>[
    _Range(8011, 8049, 'Kesehatan'), // Dokter dan praktisi kesehatan
    _Range(8211, 8299, 'Pendidikan'), // Sekolah dan kursus
    _Range(5611, 5699, 'Pakaian & Aksesori'),
    _Range(7800, 7999, 'Hiburan'),
    _Range(4800, 4899, 'Tagihan & Utilitas'),
    _Range(4100, 4199, 'Transportasi'),
    _Range(5500, 5599, 'Transportasi'),
    _Range(5800, 5899, 'Konsumsi'),
    _Range(7200, 7299, 'Jasa & Layanan'),
    _Range(7300, 7399, 'Jasa & Layanan'),
    _Range(7500, 7549, 'Jasa & Layanan'),
    _Range(5200, 5299, 'Rumah Tangga'),
    _Range(5300, 5399, 'Belanja'),
    _Range(5900, 5999, 'Belanja'),
  ];

  static const Map<int, String> _labels = <int, String>{
    5411: 'Swalayan',
    5499: 'Toko makanan',
    5812: 'Restoran',
    5814: 'Makanan cepat saji',
    5813: 'Kedai minuman',
    5462: 'Toko roti',
    5541: 'SPBU',
    5542: 'SPBU',
    7523: 'Parkir',
    4111: 'Angkutan umum',
    4121: 'Taksi / ojek',
    5912: 'Apotek',
    8062: 'Rumah sakit',
    5732: 'Toko elektronik',
    5311: 'Toko serba ada',
    7210: 'Laundry',
    7230: 'Salon',
    4814: 'Telekomunikasi',
    4900: 'Listrik / air / gas',
    8398: 'Donasi',
    5942: 'Toko buku',
  };
}

class _Range {
  const _Range(this.from, this.to, this.category);

  final int from;
  final int to;
  final String category;
}
