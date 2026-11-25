import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/thousands_separator_formatter.dart';
import '../../viewmodels/qris_viewmodel.dart';
import '../../viewmodels/scan_viewmodel.dart';
import '../widgets/category_selector.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_textfield.dart';
import '../widgets/date_input_field.dart';
import '../widgets/message_banner.dart';
import '../widgets/store_map.dart';
import 'qr_scanner_view.dart';

/// Scan QRIS: arahkan kamera ke kode QRIS toko. Nama toko, kota, kategori
/// (dari riwayat atau jenis usaha), lokasi, dan nominal (bila QRIS dinamis)
/// terisi otomatis; QRIS statis meminta Anda mengetik nominal, atau mengisinya
/// dari struk nanti.
///
/// Aplikasi ini TIDAK membayar: pembayaran tetap lewat aplikasi dompet
/// digital atau m-banking Anda. Di sini Anda hanya mencatatnya.
class QrisScanScreen extends StatefulWidget {
  const QrisScanScreen({super.key, this.scannerBuilder = cameraQrScanner});

  /// Pemindai kode QR; dapat diganti pada pengujian.
  final QrScannerBuilder scannerBuilder;

  @override
  State<QrisScanScreen> createState() => _QrisScanScreenState();
}

class _QrisScanScreenState extends State<QrisScanScreen> {
  @override
  void initState() {
    super.initState();
    // Mulai bersih: sisa pemindaian sebelumnya tidak boleh muncul lagi.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<QrisViewModel>().reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final QrisViewModel vm = context.watch<QrisViewModel>();

    return PopScope(
      // Dari formulir, "kembali" artinya memindai ulang, bukan keluar layar.
      canPop: !vm.hasData,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) vm.reset();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(vm.hasData ? 'Konfirmasi QRIS' : 'Scan QRIS'),
        ),
        body: vm.hasData
            ? _QrisForm(key: ValueKey<String>(vm.data!.payload))
            : _ScannerPane(builder: widget.scannerBuilder),
      ),
    );
  }
}

// ================================================================= pemindai

class _ScannerPane extends StatelessWidget {
  const _ScannerPane({required this.builder});

  final QrScannerBuilder builder;

  @override
  Widget build(BuildContext context) {
    final QrisViewModel vm = context.watch<QrisViewModel>();
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        builder(context, (String code) => unawaited(vm.onScanned(code))),
        // Bingkai pemandu di tengah.
        IgnorePointer(
          child: Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.emeraldLight, width: 3),
              ),
            ),
          ),
        ),
        Positioned(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: AppSpacing.lg,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (vm.scanError != null) ...[
                  MessageBanner(message: vm.scanError!),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Row(
                    children: [
                      Icon(AppIcons.qrCode, color: AppColors.emerald),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Arahkan kamera ke kode QRIS di kasir atau meja toko. '
                          'Aplikasi ini hanya mencatat, bukan membayar.',
                          style: textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================== formulir

class _QrisForm extends StatefulWidget {
  const _QrisForm({super.key});

  @override
  State<_QrisForm> createState() => _QrisFormState();
}

class _QrisFormState extends State<_QrisForm> {
  late final TextEditingController _amount;
  final TextEditingController _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    final double? amount = context.read<QrisViewModel>().amount;
    _amount = TextEditingController(
      text: amount == null ? '' : AppFormatters.amountInput(amount),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  double? _parse(String text) {
    final String digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : double.tryParse(digits);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final QrisViewModel vm = context.read<QrisViewModel>();
    // Ambil sebelum berpindah layar.
    final GoRouter router = GoRouter.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final ScanViewModel scan = context.read<ScanViewModel>();

    final QrisSaveResult? result = await vm.save();
    if (result == null || !mounted) return;

    final String message = result.isPending
        ? 'QRIS disimpan, menunggu struk. Belum dihitung sebagai pengeluaran.'
        : 'Transaksi QRIS tersimpan.';
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Scan Struk',
          onPressed: () {
            // Struk melengkapi QRIS: untuk yang menunggu, lewat konteks;
            // untuk transaksi final, lewat deteksi struk ganda.
            final pending = result.pending;
            if (pending != null) scan.beginQrisCompletion(pending);
            router.push(AppRoutes.scan);
          },
        ),
      ),
    );
    router.go(AppRoutes.dashboard);
  }

  String? _suggestionText(QrisViewModel vm) {
    switch (vm.suggestion) {
      case CategorySuggestion.history:
        return 'Sesuai pilihan Anda sebelumnya untuk toko ini.';
      case CategorySuggestion.businessType:
        final String? label = vm.data?.businessLabel;
        return label == null
            ? 'Disarankan dari jenis usaha toko.'
            : 'Disarankan dari jenis usaha: $label.';
      case CategorySuggestion.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final QrisViewModel vm = context.watch<QrisViewModel>();
    final QrisData data = vm.data!;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool waiting = vm.needsAmount && vm.waitForReceipt;
    final String? suggestion = _suggestionText(vm);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Identitas toko dari QRIS.
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: AppDecorations.card(radius: AppRadius.cardLarge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.mint,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(AppIcons.store, color: AppColors.emerald),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data.merchantName,
                                style: textTheme.titleLarge),
                            Text(
                              <String>[
                                if (data.city != null) data.city!,
                                if (data.businessLabel != null)
                                  data.businessLabel!,
                              ].join(' · '),
                              style: textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _Tag(data.isDynamic ? 'QRIS Dinamis' : 'QRIS Statis'),
                      if (data.merchantId != null) _Tag(data.merchantId!),
                      if (data.storeLabel != null) _Tag(data.storeLabel!),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Nominal.
            if (!waiting) ...[
              CustomTextField(
                label: 'Jumlah yang dibayar',
                hint: '0',
                controller: _amount,
                prefixText: 'Rp ',
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsSeparatorFormatter()],
                onChanged: (String t) => vm.setAmount(_parse(t)),
              ),
              const SizedBox(height: 6),
              Text(
                data.hasAmount
                    ? 'Nominal terbaca dari QRIS${data.fixedFee != null || data.percentFee != null ? ' (sudah termasuk biaya layanan)' : ''}.'
                    : 'QRIS ini tidak memuat nominal. Ketik jumlah yang Anda bayarkan.',
                style: textTheme.bodySmall,
              ),
            ],
            if (vm.needsAmount) ...[
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: vm.waitForReceipt,
                activeThumbColor: AppColors.emerald,
                title: const Text('Isi nominal dari struk nanti'),
                subtitle: Text(
                  'Disimpan sebagai "menunggu struk" dan belum dihitung sebagai pengeluaran sampai struknya dipindai.',
                  style: textTheme.bodySmall,
                ),
                onChanged: vm.setWaitForReceipt,
              ),
            ],
            const SizedBox(height: AppSpacing.md),

            DateInputField(
              label: 'Tanggal (hari, bulan, tahun)',
              value: vm.date,
              onChanged: vm.setDate,
            ),
            const SizedBox(height: AppSpacing.md),

            CategorySelector(
              categories: vm.categories,
              selectedId: vm.categoryId,
              onSelected: vm.selectCategory,
            ),
            if (suggestion != null) ...[
              const SizedBox(height: 6),
              Text(suggestion, style: textTheme.bodySmall),
            ],
            const SizedBox(height: AppSpacing.md),

            // Lokasi toko.
            _LocationBlock(vm: vm),
            const SizedBox(height: AppSpacing.md),

            CustomTextField(
              label: 'Catatan (opsional)',
              hint: 'Tambahkan catatan',
              controller: _notes,
              maxLines: 2,
              keyboardType: TextInputType.multiline,
              onChanged: vm.setNotes,
            ),

            if (vm.duplicates.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              MessageBanner(
                message:
                    'Mirip transaksi yang sudah tercatat: ${vm.duplicates.first.transaction.merchantName} · '
                    '${AppFormatters.longDate(vm.duplicates.first.transaction.transactionDate)} · '
                    '${AppFormatters.rupiah(vm.duplicates.first.transaction.totalAmount)}. '
                    'Pastikan ini bukan pembayaran yang sama.',
                type: BannerType.warning,
              ),
            ],
            if (vm.formError != null) ...[
              const SizedBox(height: AppSpacing.md),
              MessageBanner(message: vm.formError!),
            ],
            const SizedBox(height: AppSpacing.lg),
            CustomButton(
              label: waiting ? 'Simpan & Tunggu Struk' : 'Simpan Transaksi',
              icon: waiting ? AppIcons.hourglass : AppIcons.check,
              isLoading: vm.isSaving,
              onPressed: _save,
            ),
            const SizedBox(height: AppSpacing.sm),
            CustomButton(
              label: 'Pindai Ulang',
              icon: AppIcons.qrCode,
              variant: CustomButtonVariant.secondary,
              onPressed: vm.isSaving ? null : vm.reset,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _LocationBlock extends StatelessWidget {
  const _LocationBlock({required this.vm});

  final QrisViewModel vm;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final StoreLocation? location = vm.location;

    switch (vm.locationStatus) {
      case QrisLocationStatus.idle:
        return const SizedBox.shrink();
      case QrisLocationStatus.searching:
        return Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Mencari lokasi toko...', style: textTheme.bodySmall),
            ),
          ],
        );
      case QrisLocationStatus.notFound:
        return Text(
          'Lokasi toko tidak ditemukan di peta. Ini tidak wajib; transaksi tetap bisa disimpan.',
          style: textTheme.bodySmall,
        );
      case QrisLocationStatus.found:
        if (location == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lokasi toko', style: textTheme.labelLarge),
            const SizedBox(height: 6),
            StoreMapPreview(
              point: location.point,
              zoom: zoomForConfidence(location.confidence),
              height: 130,
            ),
            if (location.displayName.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                ScanViewModel.shortAddress(location.displayName),
                style: textTheme.bodySmall,
              ),
            ],
          ],
        );
    }
  }
}
