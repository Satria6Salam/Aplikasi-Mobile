import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/constants/category_names.dart';
import '../core/constants/db_constants.dart';
import '../data/models/category_model.dart';
import '../data/models/ml_classification_model.dart';
import '../data/models/ocr_result_model.dart';
import '../data/models/parsed_receipt_model.dart';
import '../data/models/tfidf_feature_model.dart';
import '../data/models/transaction_item_model.dart';
import '../data/models/transaction_model.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../services/image_enhancement_service.dart';
import '../services/image_format_service.dart';
import '../services/image_picker_service.dart';
import '../services/image_storage_service.dart';
import '../services/duplicate_detector.dart';
import '../services/ml_service.dart';
import '../services/ml_training_data.dart';
import '../services/ocr_service.dart';
import '../services/parsing_service.dart';
import '../services/receipt_selector.dart';
import '../services/shopping_plan_service.dart';
import '../services/store_location_service.dart';
import 'auth_viewmodel.dart';
import 'safe_change_notifier.dart';

export '../services/duplicate_detector.dart' show DuplicateMatch;
export '../services/image_picker_service.dart' show ScanSource;
export '../services/ocr_text_corrector.dart' show TextCorrection;
export '../services/store_location_service.dart'
    show
        LocationPrecision,
        LocationPrecisionLabel,
        LocationSource,
        StoreAddress,
        StoreLocation;

/// Tahapan alur pemindaian.
/// idle -> processing -> ready -> saving -> saved (atau error pada tahap mana pun).
enum ScanStatus { idle, processing, ready, saving, saved, error }

/// Tahapan pencarian lokasi toko pada pratinjau.
enum LocationLookupStatus { idle, searching, found, notFound, failed }

/// Satu barang pada pratinjau; nilainya dapat disunting pengguna.
class DraftItem {
  DraftItem({
    required this.localId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.categoryId,
    this.aiCategoryId,
    this.aiConfidence,
    this.isConfident = true,
  });

  final int localId;
  String name;
  double quantity;
  double unitPrice;
  int? categoryId;

  /// Tebakan awal AI (tidak berubah walau pengguna mengoreksi).
  final int? aiCategoryId;
  final double? aiConfidence;

  /// False bila AI kurang yakin (ditandai "Perlu dicek" pada UI).
  final bool isConfident;

  double get totalPrice => quantity * unitPrice;
}

/// Kelompok barang dengan kategori yang sama beserta subtotalnya.
class ItemGroup {
  ItemGroup({
    required this.categoryId,
    required this.categoryName,
    required this.items,
  });

  final int? categoryId;
  final String categoryName;
  final List<DraftItem> items;

  double get subtotal => items.fold<double>(
        0,
        (double sum, DraftItem item) => sum + item.totalPrice,
      );
}

/// Data pratinjau: hasil AI beserta nilai form yang boleh disunting pengguna.
class ScanDraft {
  ScanDraft({
    required this.imagePath,
    required this.source,
    required this.rawText,
    required this.parsed,
    required this.classification,
    required this.aiCategoryId,
    required this.merchantName,
    required this.transactionDate,
    required this.totalAmount,
    required this.items,
    required this.initialMerchant,
    required this.initialDate,
    required this.initialTotal,
    required this.initialItemsSignature,
    this.notes = '',
    this.qualityNotes = const <String>[],
    this.usedEnhancedImage = false,
    this.extractedAddress = StoreAddress.empty,
    String? storeAddress,
    String? storeBranch,
  })  : storeAddress = storeAddress ?? extractedAddress.fullAddress,
        storeBranch = storeBranch ?? extractedAddress.branchName ?? '';

  /// Alamat toko asli hasil ekstraksi struk (tidak berubah).
  final StoreAddress extractedAddress;

  /// Alamat dan cabang yang dapat disunting pengguna.
  String storeAddress;
  String storeBranch;

  /// Titik toko terpilih (null bila belum/tidak ditemukan).
  StoreLocation? location;
  LocationLookupStatus locationStatus = LocationLookupStatus.idle;

  /// Keterangan untuk pengguna (mis. alasan lokasi tidak ditemukan).
  String? locationMessage;

  /// Kekurangan foto yang terdeteksi (mis. "tulisan pudar"); kosong bila baik.
  final List<String> qualityNotes;

  /// True bila hasil dibaca dari foto yang sudah diperjelas otomatis.
  final bool usedEnhancedImage;

  final String imagePath;
  final ScanSource source;
  final String rawText;

  /// Hasil asli Smart Parsing (tidak berubah walau pengguna menyunting form).
  final ParsedReceiptData parsed;

  /// Klasifikasi tingkat struk (untuk catatan model AI).
  final ClassificationOutput classification;
  final int? aiCategoryId;

  // Nilai form yang dapat disunting.
  String merchantName;
  DateTime? transactionDate;
  double? totalAmount;
  final List<DraftItem> items;
  String notes;

  // Nilai awal hasil AI, untuk mendeteksi penyuntingan manual.
  final String initialMerchant;
  final DateTime? initialDate;
  final double? initialTotal;
  final String initialItemsSignature;
}

/// Mengelola alur: ambil gambar -> OCR -> parsing -> klasifikasi per barang ->
/// pratinjau/koreksi -> simpan.
class ScanViewModel extends ChangeNotifier with SafeChangeNotifier {
  ScanViewModel({
    required AuthViewModel authViewModel,
    required OcrService ocrService,
    required ParsingService parsingService,
    required MlService mlService,
    required CategoryRepository categoryRepository,
    required TransactionRepository transactionRepository,
    required ImageStorageService imageStorageService,
    required ImageFormatService imageFormatService,
    required ImagePickerService imagePickerService,
    ImageEnhancementService? imageEnhancementService,
    ReceiptSelector receiptSelector = const ReceiptSelector(),
    ShoppingPlanService? shoppingPlanService,
    StoreLocationService? storeLocationService,
    this.onTransactionSaved,
  })  : _auth = authViewModel,
        _locationService = storeLocationService,
        _duplicateDetector = DuplicateDetector(transactionRepository),
        _planService = shoppingPlanService,
        _enhancementService = imageEnhancementService,
        _selector = receiptSelector,
        _ocrService = ocrService,
        _parsingService = parsingService,
        _mlService = mlService,
        _categoryRepository = categoryRepository,
        _transactionRepository = transactionRepository,
        _imageStorageService = imageStorageService,
        _imageFormatService = imageFormatService,
        _pickerService = imagePickerService {
    _activeUserId = _auth.currentUser?.id;
    _auth.addListener(_onAuthChanged);
    if (_activeUserId != null) unawaited(_refreshModel());
  }

  static const String fieldMerchant = 'merchant';
  static const String fieldDate = 'date';
  static const String fieldAmount = 'amount';
  static const String fieldItems = 'items';

  static const String unreadableMessage = 'Gambar Tidak Jelas, Silakan Ulangi';

  final AuthViewModel _auth;
  final OcrService _ocrService;
  final ParsingService _parsingService;
  final MlService _mlService;
  final CategoryRepository _categoryRepository;
  final TransactionRepository _transactionRepository;
  final ImageStorageService _imageStorageService;
  final ImageEnhancementService? _enhancementService;
  final ReceiptSelector _selector;
  final ImageFormatService _imageFormatService;
  final ImagePickerService _pickerService;
  final ShoppingPlanService? _planService;
  final StoreLocationService? _locationService;
  final DuplicateDetector _duplicateDetector;

  List<DuplicateMatch> _duplicates = const <DuplicateMatch>[];
  Timer? _duplicateTimer;

  /// Transaksi lama yang mirip dengan struk di pratinjau (kosong bila tidak ada).
  List<DuplicateMatch> get duplicates => _duplicates;

  /// Memeriksa apakah struk ini sudah pernah dicatat (tanggal + total sama,
  /// lalu toko/barang mirip). Dipanggil otomatis saat pratinjau terbuka dan
  /// setelah tanggal/total diubah, serta sekali lagi sebelum menyimpan.
  Future<List<DuplicateMatch>> checkDuplicates() async {
    _duplicateTimer?.cancel();
    final ScanDraft? draft = _draft;
    final int? userId = _auth.currentUser?.id;
    final DateTime? date = draft?.transactionDate;
    final double? total = draft?.totalAmount;
    if (draft == null ||
        userId == null ||
        date == null ||
        total == null ||
        total <= 0) {
      if (_duplicates.isNotEmpty) {
        _duplicates = const <DuplicateMatch>[];
        safeNotify();
      }
      return const <DuplicateMatch>[];
    }

    List<DuplicateMatch> found;
    try {
      found = await _duplicateDetector.find(
        userId: userId,
        date: date,
        total: total,
        merchantName: draft.merchantName.trim(),
        itemNames: draft.items.map((DraftItem i) => i.name).toList(),
      );
    } catch (_) {
      found =
          const <DuplicateMatch>[]; // Pemeriksaan gagal tidak menghalangi simpan.
    }
    if (!identical(draft, _draft)) return const <DuplicateMatch>[];
    _duplicates = found;
    safeNotify();
    return found;
  }

  /// Menjadwalkan ulang pemeriksaan setelah pengguna berhenti mengetik.
  void _scheduleDuplicateCheck() {
    _duplicateTimer?.cancel();
    _duplicateTimer = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(checkDuplicates()),
    );
  }

  /// Penanda permintaan lokasi terbaru; hasil permintaan lama diabaikan.
  int _locationToken = 0;

  /// True bila fitur lokasi toko tersedia (layanan terpasang).
  bool get locationEnabled => _locationService != null;

  List<String> _lastPlanMatches = const <String>[];

  /// Nama barang rencana belanja yang tercoret oleh struk terakhir yang disimpan.
  List<String> get lastPlanMatches => _lastPlanMatches;

  /// Dipanggil setelah transaksi tersimpan (misalnya untuk memuat ulang Dasbor).
  final VoidCallback? onTransactionSaved;

  ScanStatus _status = ScanStatus.idle;
  String? _errorMessage;
  String? _progressMessage;
  ScanDraft? _draft;
  List<CategoryModel> _categories = <CategoryModel>[];
  final Map<String, String> _formErrors = <String, String>{};
  Duration? _lastProcessingDuration;
  int? _activeUserId;
  int _nextItemId = 1;

  ScanStatus get status => _status;
  String? get errorMessage => _errorMessage;

  /// Keterangan langkah yang sedang berjalan (untuk indikator loading).
  String? get progressMessage => _progressMessage;
  ScanDraft? get draft => _draft;
  List<CategoryModel> get categories => _categories;
  Map<String, String> get formErrors =>
      Map<String, String>.unmodifiable(_formErrors);

  /// Lama proses OCR + parsing + klasifikasi terakhir (target maksimal 3 detik).
  Duration? get lastProcessingDuration => _lastProcessingDuration;

  bool get isProcessing => _status == ScanStatus.processing;
  bool get isSaving => _status == ScanStatus.saving;
  bool get isBusy => isProcessing || isSaving;
  bool get hasDraft => _draft != null;

  /// Jumlah harga seluruh barang pada pratinjau.
  double get itemsTotal {
    final ScanDraft? draft = _draft;
    if (draft == null) return 0;
    return draft.items.fold<double>(
      0,
      (double sum, DraftItem item) => sum + item.totalPrice,
    );
  }

  /// True bila total struk berbeda dari jumlah harga barang (mis. ada pajak/diskon).
  bool get hasTotalMismatch {
    final ScanDraft? draft = _draft;
    final double? total = draft?.totalAmount;
    if (draft == null || total == null || draft.items.isEmpty) return false;
    // Struk berpajak/berpembulatan: barang dibandingkan dengan subtotalnya,
    // bukan dengan total akhir, selama total belum diubah pengguna.
    final ParsedReceiptData parsed = draft.parsed;
    final double? parsedTotal = parsed.totalAmount;
    final bool totalUntouched =
        parsedTotal != null && (total - parsedTotal).abs() <= 1;
    if (totalUntouched && parsed.hasBreakdown) {
      return !parsed.itemsMatch(itemsTotal);
    }
    return (itemsTotal - total).abs() > 1;
  }

  /// Barang dikelompokkan per kategori, subtotal terbesar lebih dulu.
  List<ItemGroup> get groupedItems {
    final ScanDraft? draft = _draft;
    if (draft == null) return <ItemGroup>[];

    final Map<int?, ItemGroup> groups = <int?, ItemGroup>{};
    for (final DraftItem item in draft.items) {
      final ItemGroup group = groups.putIfAbsent(
        item.categoryId,
        () => ItemGroup(
          categoryId: item.categoryId,
          categoryName: categoryNameOf(item.categoryId),
          items: <DraftItem>[],
        ),
      );
      group.items.add(item);
    }
    final List<ItemGroup> result = groups.values.toList()
      ..sort((ItemGroup a, ItemGroup b) => b.subtotal.compareTo(a.subtotal));
    return result;
  }

  /// Nama kategori untuk sebuah ID ('Tanpa kategori' bila tidak ditemukan).
  String categoryNameOf(int? categoryId) {
    for (final CategoryModel category in _categories) {
      if (category.id == categoryId) return category.name;
    }
    return 'Tanpa kategori';
  }

  Future<void> loadCategories() async {
    await _ensureCategories();
    safeNotify();
  }

  /// Memuat ulang kategori tiap kali dibutuhkan agar perubahan dari layar
  /// Kelola Kategori langsung terbaca. Kategori tersembunyi tidak dipakai.
  Future<void> _ensureCategories() async {
    final List<CategoryModel> loaded = List<CategoryModel>.of(
      (await _categoryRepository.getAll())
          .where((CategoryModel c) => !c.isHidden),
    );
    // "Lainnya" selalu di urutan terakhir agar mudah dicari.
    loaded.sort((CategoryModel a, CategoryModel b) {
      final int byRank =
          CategoryNames.rank(a.name).compareTo(CategoryNames.rank(b.name));
      return byRank != 0 ? byRank : (a.id ?? 0).compareTo(b.id ?? 0);
    });
    _categories = loaded;
  }

  // ------------------------------------------------------ ambil & proses

  /// Membuka kamera/galeri/file, lalu langsung memproses gambar yang dipilih.
  Future<void> pickAndProcess(ScanSource source) async {
    if (isBusy) return;
    try {
      final String? path = await _pickerService.pick(source);
      if (path == null) return; // Pengguna membatalkan pemilihan.
      await processImage(imagePath: path, source: source);
    } on ImagePickException catch (e) {
      _setError(e.message);
    } catch (_) {
      _setError('Gagal mengambil gambar. Silakan coba lagi.');
    }
  }

  /// Cek format -> OCR -> cek keterbacaan -> parsing -> klasifikasi tiap barang -> pratinjau.
  Future<void> processImage({
    required String imagePath,
    required ScanSource source,
  }) async {
    if (isBusy) return;
    if (_auth.currentUser?.id == null) {
      _setError('Sesi berakhir. Silakan login kembali.');
      return;
    }

    _draft = null;
    _duplicates = const <DuplicateMatch>[];
    _duplicateTimer?.cancel();
    _formErrors.clear();
    _errorMessage = null;
    _status = ScanStatus.processing;
    _progressMessage = 'Memeriksa format gambar...';
    safeNotify();

    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      await _ensureCategories();
      final String preparedPath = await _imageFormatService.prepare(imagePath);

      await _setProgress('Membaca teks struk...');
      final OcrResult firstOcr =
          await _ocrService.recognizeFromFile(preparedPath);
      ReceiptReading reading = ReceiptReading(
        rawText: firstOcr.rawText,
        parsed: _parsingService.parse(firstOcr.rawText),
      );
      bool readable = firstOcr.isReadable;
      List<String> qualityNotes = const <String>[];

      // Hasil belum lengkap atau angkanya tidak cocok: perjelas foto
      // (ratakan cahaya, pertegas tulisan pudar), baca ulang, lalu pilih
      // hasil yang lebih baik.
      final ImageEnhancementService? enhancer = _enhancementService;
      if (enhancer != null &&
          !(readable && _selector.isComplete(reading.parsed))) {
        await _setProgress('Memperjelas foto struk...');
        final EnhancedImage? enhanced = await enhancer.enhance(preparedPath);
        if (enhanced != null) {
          qualityNotes = enhanced.quality.notes;
          try {
            final OcrResult secondOcr =
                await _ocrService.recognizeFromFile(enhanced.path);
            if (secondOcr.isReadable) {
              final ReceiptReading second = ReceiptReading(
                rawText: secondOcr.rawText,
                parsed: _parsingService.parse(secondOcr.rawText),
                fromEnhancedImage: true,
              );
              reading = readable ? _selector.choose(reading, second) : second;
              readable = true;
            }
          } on OcrException {
            // Bacaan kedua gagal: tetap pakai hasil dari foto asli.
          } finally {
            await enhancer.discard(enhanced);
          }
        }
      }

      if (!readable) {
        _setError(unreadableMessage);
        return;
      }

      await _setProgress('Mengekstrak data transaksi...');
      final ParsedReceiptData parsed = reading.parsed;

      await _setProgress('Mengklasifikasikan setiap barang...');
      await _mlService.initialize();
      final ClassificationOutput receiptLevel =
          _mlService.classify(parsed.classificationText);
      final CategoryModel? receiptCategory =
          _findCategory(receiptLevel.categoryName);

      final List<DraftItem> items = <DraftItem>[];
      for (final ParsedItem parsedItem in parsed.items) {
        final ClassificationOutput out = _mlService.classifyItem(
          parsedItem.name,
          merchantName: parsed.merchantName,
        );
        final CategoryModel? category = _findCategory(out.categoryName);
        items.add(
          DraftItem(
            localId: _nextItemId++,
            name: parsedItem.name,
            quantity: parsedItem.quantity,
            unitPrice: parsedItem.unitPrice,
            categoryId: category?.id,
            aiCategoryId: category?.id,
            aiConfidence: out.probability,
            isConfident: out.isConfident,
          ),
        );
      }

      // Tidak ada barang terbaca tetapi total diketahui: buat satu barang agar bisa disunting.
      final double? parsedTotal = parsed.totalAmount;
      if (items.isEmpty && parsedTotal != null && parsedTotal > 0) {
        final String merchant = parsed.merchantName ?? '';
        items.add(
          DraftItem(
            localId: _nextItemId++,
            name: merchant.isEmpty ? 'Pembelian' : 'Pembelian di $merchant',
            quantity: 1,
            unitPrice: parsedTotal,
            categoryId: receiptCategory?.id,
            aiCategoryId: receiptCategory?.id,
            aiConfidence: receiptLevel.probability,
            isConfident: receiptLevel.isConfident,
          ),
        );
      }

      final double itemsSum = items.fold<double>(
        0,
        (double sum, DraftItem item) => sum + item.totalPrice,
      );
      final double? initialTotal =
          parsedTotal ?? (items.isEmpty ? null : itemsSum);

      stopwatch.stop();
      _lastProcessingDuration = stopwatch.elapsed;

      _draft = ScanDraft(
        imagePath: preparedPath,
        source: source,
        rawText: reading.rawText,
        parsed: parsed,
        classification: receiptLevel,
        aiCategoryId: receiptCategory?.id,
        merchantName: parsed.merchantName ?? '',
        transactionDate: parsed.transactionDate,
        totalAmount: initialTotal,
        items: items,
        initialMerchant: (parsed.merchantName ?? '').trim(),
        initialDate: parsed.transactionDate,
        initialTotal: initialTotal,
        initialItemsSignature: _signature(items),
        qualityNotes: qualityNotes,
        usedEnhancedImage: reading.fromEnhancedImage,
        extractedAddress: parsed.address,
      );
      _status = ScanStatus.ready;
      _progressMessage = null;
      safeNotify();
      // Lokasi dan pemeriksaan struk ganda berjalan di latar belakang agar
      // pratinjau langsung tampil.
      unawaited(_lookupLocation(fromReceipt: true));
      unawaited(checkDuplicates());
    } on ImageFormatException catch (e) {
      _setError(e.message);
    } on OcrException catch (e) {
      _setError(e.message);
    } catch (_) {
      _setError('Terjadi kesalahan saat memproses struk. Silakan coba lagi.');
    }
  }

  CategoryModel? _findCategory(String name) {
    CategoryModel? fallback;
    for (final CategoryModel category in _categories) {
      if (category.name.toLowerCase() == name.toLowerCase()) return category;
      if (category.name == MlService.fallbackCategory) fallback = category;
    }
    return fallback ?? (_categories.isEmpty ? null : _categories.first);
  }

  Future<void> _setProgress(String message) async {
    _progressMessage = message;
    safeNotify();
    // Beri kesempatan UI menggambar ulang sebelum langkah berikutnya.
    await Future<void>.delayed(Duration.zero);
  }

  void _setError(String message) {
    _status = ScanStatus.error;
    _errorMessage = message;
    _progressMessage = null;
    _draft = null;
    safeNotify();
  }

  // -------------------------------------------------------- edit pratinjau
  // Perubahan teks (merchant, total, catatan) tidak memicu rebuild agar kursor
  // pada TextField tidak melompat; rebuild hanya bila ada pesan galat yang perlu hilang.

  void updateMerchantName(String value) {
    final ScanDraft? draft = _draft;
    if (draft == null) return;
    draft.merchantName = value;
    _clearFieldError(fieldMerchant);
    _scheduleDuplicateCheck();
  }

  void updateTotalAmountText(String text) {
    final ScanDraft? draft = _draft;
    if (draft == null) return;
    draft.totalAmount = parseAmountInput(text);
    _clearFieldError(fieldAmount);
    _scheduleDuplicateCheck();
    safeNotify(); // Peringatan selisih total perlu diperbarui.
  }

  void updateNotes(String value) {
    _draft?.notes = value;
  }

  void updateTransactionDate(DateTime? value) {
    final ScanDraft? draft = _draft;
    if (draft == null) return;
    draft.transactionDate = value;
    _formErrors.remove(fieldDate);
    safeNotify();
    unawaited(checkDuplicates());
  }

  /// Mengganti total struk dengan jumlah harga seluruh barang.
  void useItemsTotal() {
    final ScanDraft? draft = _draft;
    if (draft == null) return;
    draft.totalAmount = itemsTotal;
    _formErrors.remove(fieldAmount);
    safeNotify();
  }

  void _clearFieldError(String field) {
    if (_formErrors.remove(field) != null) safeNotify();
  }

  // ---------------------------------------------------------- lokasi toko

  /// Struk dianggap difoto di toko bila dari kamera pada hari transaksi;
  /// hanya saat itu posisi GPS dipakai untuk menyaring hasil pencarian.
  bool _gpsRepresentsStore(ScanDraft draft) {
    if (draft.source != ScanSource.camera) return false;
    final DateTime? date = draft.transactionDate;
    if (date == null) return true;
    final DateTime now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// Nama toko untuk pencarian; cabang ditambahkan agar lebih spesifik
  /// (mis. "Indomaret Urek Urek").
  String _searchName(ScanDraft draft) {
    final String merchant = draft.merchantName.trim();
    final String branch = draft.storeBranch.trim();
    if (branch.isEmpty ||
        merchant.toLowerCase().contains(branch.toLowerCase())) {
      return merchant;
    }
    return '$merchant $branch';
  }

  /// Mencari lokasi toko. [fromReceipt] true memakai alamat asli struk
  /// (dan riwayat cache); false memakai alamat yang sudah disunting.
  Future<void> _lookupLocation({required bool fromReceipt}) async {
    final ScanDraft? draft = _draft;
    final StoreLocationService? service = _locationService;
    final int? userId = _auth.currentUser?.id;
    if (draft == null || service == null || userId == null) return;

    final int token = ++_locationToken;
    StoreAddress address = fromReceipt
        ? draft.extractedAddress
        : service.parseAddress(draft.storeAddress,
            merchantName: draft.merchantName);
    final String branch = draft.storeBranch.trim();
    if (address.isNotEmpty && branch.isNotEmpty) {
      address = address.copyWith(branchName: branch);
    }
    final bool useGps = _gpsRepresentsStore(draft);

    if (address.isEmpty && !useGps) {
      draft
        ..location = fromReceipt ? null : draft.location
        ..locationStatus = LocationLookupStatus.notFound
        ..locationMessage = draft.storeAddress.trim().isEmpty
            ? 'Alamat toko tidak tercantum di struk. Isi alamat, pakai lokasi Anda, atau atur titik di peta.'
            : 'Alamat belum cukup lengkap untuk dicari. Tambahkan nama jalan, kecamatan, atau kota.';
      safeNotify();
      return;
    }

    draft
      ..locationStatus = LocationLookupStatus.searching
      ..locationMessage = null;
    safeNotify();

    try {
      final StoreLocation? found = await service.lookup(
        userId: userId,
        merchantName: draft.merchantName.trim(),
        address: address,
        cacheAddress: fromReceipt && draft.extractedAddress.isNotEmpty
            ? draft.extractedAddress.fullAddress
            : null,
        useGps: useGps,
      );
      if (token != _locationToken || !identical(draft, _draft)) return;
      draft.location = found;
      if (found == null) {
        draft
          ..locationStatus = LocationLookupStatus.notFound
          ..locationMessage =
              'Lokasi tidak ditemukan di peta. Periksa ejaan alamat atau atur titik secara manual.';
      } else {
        draft
          ..locationStatus = LocationLookupStatus.found
          ..locationMessage = found.isAccurate
              ? null
              : 'Lokasi masih perkiraan (${found.precision.label}). Geser pin bila kurang tepat.';
      }
    } on GeocodingException catch (e) {
      if (token != _locationToken || !identical(draft, _draft)) return;
      draft
        ..locationStatus = LocationLookupStatus.failed
        ..locationMessage = e.message;
    } catch (_) {
      if (token != _locationToken || !identical(draft, _draft)) return;
      draft
        ..locationStatus = LocationLookupStatus.failed
        ..locationMessage = 'Gagal mencari lokasi toko. Silakan coba lagi.';
    }
    safeNotify();
  }

  void updateStoreAddress(String value) {
    _draft?.storeAddress = value;
  }

  void updateStoreBranch(String value) {
    _draft?.storeBranch = value;
  }

  /// Nama toko + cabang yang dipakai untuk pencarian (ditampilkan di UI).
  String get locationSearchName {
    final ScanDraft? draft = _draft;
    return draft == null ? '' : _searchName(draft);
  }

  /// Mencari ulang lokasi dari alamat yang sudah disunting pengguna.
  Future<void> searchLocation() => _lookupLocation(fromReceipt: false);

  /// Memakai posisi GPS perangkat sebagai lokasi toko.
  Future<void> useCurrentLocation() async {
    final ScanDraft? draft = _draft;
    final StoreLocationService? service = _locationService;
    if (draft == null || service == null) return;

    final int token = ++_locationToken;
    final LocationLookupStatus previous = draft.locationStatus;
    draft
      ..locationStatus = LocationLookupStatus.searching
      ..locationMessage = 'Membaca posisi GPS...';
    safeNotify();

    final DeviceLocationResult result = await service.currentPosition();
    if (token != _locationToken || !identical(draft, _draft)) return;
    final DevicePosition? position = result.position;
    if (position == null) {
      draft
        ..locationStatus = draft.location == null
            ? (previous == LocationLookupStatus.found
                ? LocationLookupStatus.notFound
                : LocationLookupStatus.failed)
            : LocationLookupStatus.found
        ..locationMessage = result.message;
      safeNotify();
      return;
    }
    await _applyManualPoint(draft, token, position.point,
        source: LocationSource.gps,
        confidence: position.accuracyMeters <= 50 ? 0.85 : 0.65);
  }

  /// Titik yang dipilih/digeser pengguna di peta.
  Future<void> setManualLocation(LatLng point) async {
    final ScanDraft? draft = _draft;
    if (draft == null || _locationService == null) return;
    final int token = ++_locationToken;
    await _applyManualPoint(draft, token, point,
        source: LocationSource.manual, confidence: 0.95);
  }

  Future<void> _applyManualPoint(
    ScanDraft draft,
    int token,
    LatLng point, {
    required String source,
    required double confidence,
  }) async {
    draft
      ..location = StoreLocation(
        point: point,
        displayName: draft.location?.displayName ?? '',
        precision: LocationPrecision.store,
        confidence: confidence,
        source: source,
      )
      ..locationStatus = LocationLookupStatus.found
      ..locationMessage = null;
    safeNotify();

    // Lengkapi keterangan alamat menurut peta (tidak wajib berhasil).
    final String? described = await _locationService?.describe(point);
    if (token != _locationToken || !identical(draft, _draft)) return;
    final StoreLocation? current = draft.location;
    if (current != null && described != null) {
      draft.location = current.copyWith(displayName: described);
      if (draft.storeAddress.trim().isEmpty) {
        draft.storeAddress = shortAddress(described);
      }
      safeNotify();
    }
  }

  /// Alamat versi peta tanpa nama negara.
  static String shortAddress(String displayName) => displayName
      .split(',')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty && s != 'Indonesia')
      .join(', ');

  void clearLocation() {
    final ScanDraft? draft = _draft;
    if (draft == null) return;
    _locationToken++;
    draft
      ..location = null
      ..locationStatus = LocationLookupStatus.idle
      ..locationMessage = null;
    safeNotify();
  }

  // ---------------------------------------------------------- edit barang

  /// Menambah barang baru ke pratinjau.
  void addItem({
    required String name,
    required double quantity,
    required double unitPrice,
    required int categoryId,
  }) {
    final ScanDraft? draft = _draft;
    if (draft == null) return;
    draft.items.add(
      DraftItem(
        localId: _nextItemId++,
        name: name.trim(),
        quantity: quantity,
        unitPrice: unitPrice,
        categoryId: categoryId,
        aiCategoryId: null,
      ),
    );
    _formErrors.remove(fieldItems);
    safeNotify();
  }

  /// Mengubah nama, jumlah, harga, atau kategori sebuah barang.
  void updateItem(
    int localId, {
    required String name,
    required double quantity,
    required double unitPrice,
    required int categoryId,
  }) {
    final ScanDraft? draft = _draft;
    if (draft == null) return;
    for (final DraftItem item in draft.items) {
      if (item.localId == localId) {
        item
          ..name = name.trim()
          ..quantity = quantity
          ..unitPrice = unitPrice
          ..categoryId = categoryId;
        break;
      }
    }
    safeNotify();
  }

  void removeItem(int localId) {
    final ScanDraft? draft = _draft;
    if (draft == null) return;
    draft.items.removeWhere((DraftItem item) => item.localId == localId);
    safeNotify();
  }

  /// Saran kategori untuk nama barang yang sedang diketik (dipakai pada editor barang).
  int? suggestCategoryId(String name) {
    if (name.trim().isEmpty) return null;
    final ClassificationOutput out = _mlService.classifyItem(
      name,
      merchantName: _draft?.merchantName,
    );
    return _findCategory(out.categoryName)?.id;
  }

  /// Mengubah teks nominal ("17.000", "Rp 17.000,50", "17000") menjadi angka.
  /// Titik dianggap pemisah ribuan dan koma sebagai desimal (format Indonesia).
  static double? parseAmountInput(String text) {
    final String cleaned = text
        .replaceAll(RegExp(r'[Rr][Pp]'), '')
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll('.', '')
        .replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  /// Memeriksa form pratinjau. Kunci peta: lihat konstanta `field*`.
  Map<String, String> validateForm() {
    final Map<String, String> errors = <String, String>{};
    final ScanDraft? draft = _draft;
    if (draft == null) return errors;

    if (draft.merchantName.trim().isEmpty) {
      errors[fieldMerchant] = 'Nama merchant wajib diisi';
    }
    if (draft.transactionDate == null) {
      errors[fieldDate] = 'Tanggal transaksi wajib diisi';
    }
    final double? amount = draft.totalAmount;
    if (amount == null || amount <= 0) {
      errors[fieldAmount] = 'Total belanja harus lebih dari 0';
    }
    if (draft.items.isEmpty) {
      errors[fieldItems] = 'Tambahkan minimal satu barang';
    } else {
      for (final DraftItem item in draft.items) {
        if (item.name.trim().isEmpty ||
            item.unitPrice <= 0 ||
            item.quantity <= 0 ||
            item.categoryId == null) {
          errors[fieldItems] =
              'Lengkapi nama, harga, dan kategori setiap barang';
          break;
        }
      }
    }
    return errors;
  }

  // ---------------------------------------------------------------- simpan

  /// Menyimpan transaksi (beserta rincian barang, jejak OCR, parsing,
  /// klasifikasi, dan TF-IDF) ke basis data lokal. Mengembalikan true bila berhasil.
  Future<bool> saveTransaction() async {
    final ScanDraft? draft = _draft;
    final int? userId = _auth.currentUser?.id;
    if (draft == null || isBusy) return false;
    if (userId == null) {
      _setError('Sesi berakhir. Silakan login kembali.');
      return false;
    }

    final Map<String, String> errors = validateForm();
    _formErrors
      ..clear()
      ..addAll(errors);
    if (errors.isNotEmpty) {
      safeNotify();
      return false;
    }

    final DateTime? date = draft.transactionDate;
    final double? amount = draft.totalAmount;
    final int? dominantCategory = _dominantCategoryId(draft);
    if (date == null || amount == null || dominantCategory == null) {
      return false;
    }

    _status = ScanStatus.saving;
    _errorMessage = null;
    safeNotify();

    String? storedImagePath;
    try {
      storedImagePath =
          await _imageStorageService.persistImage(draft.imagePath);
      final DateTime now = DateTime.now();

      final OcrResultModel ocr = OcrResultModel(
        userId: userId,
        imagePath: storedImagePath,
        rawText: draft.rawText,
        ocrSource: draft.source.dbValue,
        ocrStatus: OcrStatus.success,
        createdAt: now,
      );
      final ParsedReceiptModel parsed = ParsedReceiptModel(
        ocrId: 0, // Diisi repository setelah OCR tersimpan.
        merchantName: draft.parsed.merchantName,
        transactionDate: draft.parsed.transactionDate,
        totalAmount: draft.parsed.totalAmount,
        parsingStatus: draft.parsed.status,
        createdAt: now,
      );
      final ClassificationOutput output = draft.classification;
      final MlClassificationModel classification = MlClassificationModel(
        parsedId: 0, // Diisi repository setelah parsing tersimpan.
        inputText: output.inputText,
        preprocessedText: output.preprocessedText,
        predictedCategoryId: draft.aiCategoryId,
        predictionProbability: output.probability,
        modelName: output.modelName,
        modelVersion: output.modelVersion,
        classificationStatus: ClassificationStatus.success,
        createdAt: now,
      );
      final List<TfidfFeatureModel> features = output.terms
          .map(
            (TfidfTerm t) => TfidfFeatureModel(
              classificationId: 0, // Diisi repository.
              term: t.term,
              tf: t.tf,
              idf: t.idf,
              tfidfWeight: t.weight,
            ),
          )
          .toList();
      final List<TransactionItemModel> items = draft.items
          .map(
            (DraftItem d) => TransactionItemModel(
              transactionId: 0, // Diisi repository.
              name: d.name.trim(),
              quantity: d.quantity,
              unitPrice: d.unitPrice,
              totalPrice: d.totalPrice,
              categoryId: d.categoryId ?? dominantCategory,
              aiCategoryId: d.aiCategoryId,
              aiConfidence: d.aiConfidence,
              createdAt: now,
            ),
          )
          .toList();
      final String notes = draft.notes.trim();
      final String address = draft.storeAddress.trim();
      final String branch = draft.storeBranch.trim();
      final StoreLocation? location = draft.location;
      final TransactionModel transaction = TransactionModel(
        userId: userId,
        merchantName: draft.merchantName.trim(),
        transactionDate: date,
        totalAmount: amount,
        categoryId: dominantCategory,
        isManualEdit: _isManuallyEdited(draft),
        notes: notes.isEmpty ? null : notes,
        createdAt: now,
        updatedAt: now,
        storeBranch: branch.isEmpty ? null : branch,
        storeAddress: address.isEmpty ? null : address,
        latitude: location?.point.latitude,
        longitude: location?.point.longitude,
        locationPrecision: location?.precision.name,
        locationSource: location?.source,
      );

      final TransactionModel saved =
          await _transactionRepository.saveScanTransaction(
        ocr: ocr,
        parsed: parsed,
        classification: classification,
        features: features,
        transaction: transaction,
        items: items,
      );

      if (location != null && draft.extractedAddress.isNotEmpty) {
        await _locationService?.remember(
          userId: userId,
          merchantName: draft.merchantName.trim(),
          address: draft.extractedAddress.fullAddress,
          location: location,
        );
      }
      _lastPlanMatches = await _markPlannedItems(userId, saved, items);
      _draft = null;
      _formErrors.clear();
      _status = ScanStatus.saved;
      safeNotify();
      onTransactionSaved?.call();
      unawaited(_refreshModel()); // Model belajar dari koreksi terbaru.
      return true;
    } catch (_) {
      if (storedImagePath != null) {
        await _imageStorageService.deleteImage(storedImagePath);
      }
      _status = ScanStatus.ready;
      _errorMessage = 'Gagal menyimpan transaksi. Silakan coba lagi.';
      safeNotify();
      return false;
    }
  }

  /// Mencoret rencana belanja yang cocok dengan barang pada struk.
  /// Kegagalan di sini tidak membatalkan transaksi yang sudah tersimpan.
  Future<List<String>> _markPlannedItems(
    int userId,
    TransactionModel saved,
    List<TransactionItemModel> items,
  ) async {
    final ShoppingPlanService? service = _planService;
    if (service == null || items.isEmpty) return const <String>[];
    try {
      final List<PlanMatch> matches = await service.markPurchasedFromReceipt(
        userId: userId,
        transactionId: saved.id,
        purchasedAt: saved.transactionDate,
        lines: <PurchasedLine>[
          for (final TransactionItemModel item in items)
            PurchasedLine(
              name: item.name,
              quantity: item.quantity,
              totalPrice: item.totalPrice,
            ),
        ],
      );
      return matches.map((PlanMatch m) => m.plan.name).toList();
    } catch (_) {
      return const <String>[];
    }
  }

  /// Kategori dengan jumlah harga terbesar; menjadi kategori utama transaksi.
  int? _dominantCategoryId(ScanDraft draft) {
    final Map<int, double> totals = <int, double>{};
    for (final DraftItem item in draft.items) {
      final int? id = item.categoryId;
      if (id == null) continue;
      totals[id] = (totals[id] ?? 0) + item.totalPrice;
    }
    int? best;
    double bestValue = -1;
    totals.forEach((int id, double value) {
      if (value > bestValue) {
        bestValue = value;
        best = id;
      }
    });
    return best;
  }

  String _signature(List<DraftItem> items) {
    return items
        .map(
          (DraftItem i) =>
              '${i.name.trim().toLowerCase()}|${i.quantity}|${i.unitPrice.round()}|${i.categoryId}',
        )
        .join('#');
  }

  /// True bila ada nilai form yang berbeda dari hasil AI (kolom is_manual_edit).
  bool _isManuallyEdited(ScanDraft draft) {
    if (draft.merchantName.trim() != draft.initialMerchant) return true;
    if (!_sameDay(draft.transactionDate, draft.initialDate)) return true;

    final double? initial = draft.initialTotal;
    final double? amount = draft.totalAmount;
    if (amount == null || initial == null) {
      if (amount != initial) return true;
    } else if ((amount - initial).abs() > 0.5) {
      return true;
    }
    return _signature(draft.items) != draft.initialItemsSignature;
  }

  bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == b;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // ------------------------------------------------- belajar dari koreksi

  /// Melatih ulang model AI dengan barang yang pernah divalidasi pengguna,
  /// sehingga tebakan kategori makin sesuai kebiasaan pengguna.
  Future<void> _refreshModel() async {
    final int? userId = _auth.currentUser?.id;
    if (userId == null) return;
    try {
      final List<LabeledItem> labeled =
          await _transactionRepository.getTrainingSamples(userId);
      _mlService.learn(
        labeled
            .map((LabeledItem l) => LabeledSample(l.name, l.categoryName))
            .toList(),
      );
    } catch (_) {
      // Model dasar tetap dipakai bila gagal memuat riwayat.
    }
  }

  // ------------------------------------------------------------------ reset

  /// Membatalkan proses dan membuang data sementara (tidak ada yang disimpan).
  void cancel() => reset();

  void reset() {
    _locationToken++;
    _duplicateTimer?.cancel();
    _duplicates = const <DuplicateMatch>[];
    _status = ScanStatus.idle;
    _errorMessage = null;
    _progressMessage = null;
    _draft = null;
    _formErrors.clear();
    safeNotify();
  }

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    safeNotify();
  }

  void _onAuthChanged() {
    final int? userId = _auth.currentUser?.id;
    if (userId == _activeUserId) return;
    _activeUserId = userId;
    reset();
    if (userId != null) unawaited(_refreshModel());
  }

  @override
  void dispose() {
    _duplicateTimer?.cancel();
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
