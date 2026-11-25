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
import '../../data/models/qris_pending_model.dart';
import '../../viewmodels/qris_pending_viewmodel.dart';
import '../../viewmodels/scan_viewmodel.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_textfield.dart';
import '../widgets/date_input_field.dart';
import '../widgets/empty_state.dart';
import '../widgets/message_banner.dart';
import '../widgets/sheet_frame.dart';

/// QRIS yang sudah dipindai tetapi nominalnya belum diketahui. Dilengkapi
/// dengan memindai struknya (nominal dan barang terisi otomatis), atau dengan
/// mengisi nominal sendiri. Belum dihitung sebagai pengeluaran.
class QrisPendingScreen extends StatefulWidget {
  const QrisPendingScreen({super.key});

  @override
  State<QrisPendingScreen> createState() => _QrisPendingScreenState();
}

class _QrisPendingScreenState extends State<QrisPendingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(context.read<QrisPendingViewModel>().load());
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _scanReceipt(QrisPendingModel pending) async {
    final ScanViewModel scan = context.read<ScanViewModel>();
    final QrisPendingViewModel vm = context.read<QrisPendingViewModel>();
    scan.beginQrisCompletion(pending);
    await context.push(AppRoutes.scan);
    // Kembali dari kamera (mis. struk sudah disimpan): segarkan daftar.
    if (mounted) await vm.load();
  }

  Future<void> _fillAmount(QrisPendingModel pending) async {
    final QrisPendingViewModel vm = context.read<QrisPendingViewModel>();
    final ({double amount, DateTime date})? input =
        await showAppSheet<({double amount, DateTime date})>(
      context,
      (BuildContext _) => _AmountSheet(pending: pending),
    );
    if (input == null || !mounted) return;
    final saved = await vm.completeWithAmount(
      pending,
      amount: input.amount,
      date: input.date,
    );
    if (!mounted) return;
    _snack(saved == null
        ? vm.errorMessage ?? 'Gagal menyimpan.'
        : 'Transaksi ${pending.merchantName} ${AppFormatters.rupiah(input.amount)} tersimpan.');
  }

  Future<void> _delete(QrisPendingModel pending) async {
    final QrisPendingViewModel vm = context.read<QrisPendingViewModel>();
    final bool ok = await showConfirmDialog(
      context,
      title: 'Hapus catatan QRIS?',
      message:
          'Catatan QRIS ${pending.merchantName} yang menunggu struk akan dihapus.',
      confirmLabel: 'Hapus',
      isDestructive: true,
    );
    if (ok) await vm.delete(pending);
  }

  @override
  Widget build(BuildContext context) {
    final QrisPendingViewModel vm = context.watch<QrisPendingViewModel>();
    final TextTheme textTheme = Theme.of(context).textTheme;

    Widget body;
    if (vm.isLoading && vm.items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (vm.items.isEmpty) {
      body = ListView(
        children: [
          if (vm.errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: MessageBanner(message: vm.errorMessage!),
            ),
          EmptyState(
            icon: AppIcons.qrCode,
            title: 'Tidak ada QRIS yang menunggu',
            message:
                'Saat memindai QRIS tanpa nominal, pilih "Isi nominal dari struk nanti". Catatannya muncul di sini sampai Anda memindai struknya.',
          ),
        ],
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          MessageBanner(
            message:
                'Catatan di bawah belum dihitung sebagai pengeluaran. Pindai struknya agar nominal dan barang terisi otomatis.',
            type: BannerType.warning,
          ),
          if (vm.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            MessageBanner(message: vm.errorMessage!),
          ],
          for (final QrisPendingModel p in vm.items)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: AppDecorations.card(radius: AppRadius.cardLarge),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(AppIcons.hourglass,
                            size: 20, color: AppColors.warningDeep),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.merchantName,
                                  style: textTheme.titleMedium),
                              Text(
                                <String>[
                                  if (p.city != null) p.city!,
                                  'dipindai ${AppFormatters.longDate(p.scannedAt)}',
                                ].join(' · '),
                                style: textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Hapus',
                          icon: Icon(AppIcons.trash, size: 20),
                          onPressed: () => _delete(p),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: CustomButton(
                            label: 'Scan Struk',
                            icon: AppIcons.scanLine,
                            onPressed: () => _scanReceipt(p),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CustomButton(
                            label: 'Isi Nominal',
                            icon: AppIcons.pencil,
                            variant: CustomButtonVariant.secondary,
                            onPressed: () => _fillAmount(p),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('QRIS Menunggu Struk')),
      body: SafeArea(child: body),
    );
  }
}

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({required this.pending});

  final QrisPendingModel pending;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  final TextEditingController _amount = TextEditingController();
  DateTime? _date = () {
    final DateTime n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    final String digits = _amount.text.replaceAll(RegExp(r'[^0-9]'), '');
    final double? amount = digits.isEmpty ? null : double.tryParse(digits);
    final DateTime? date = _date;
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Isi jumlah yang Anda bayarkan');
      return;
    }
    if (date == null) {
      setState(() => _error = 'Tanggal belum valid');
      return;
    }
    Navigator.of(context).pop((amount: amount, date: date));
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: 'Isi nominal ${widget.pending.merchantName}',
      subtitle: 'Dicatat sebagai transaksi QRIS tanpa rincian barang.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomTextField(
            label: 'Jumlah yang dibayar',
            hint: '0',
            controller: _amount,
            prefixText: 'Rp ',
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsSeparatorFormatter()],
            errorText: _error,
          ),
          const SizedBox(height: AppSpacing.md),
          DateInputField(
            label: 'Tanggal (hari, bulan, tahun)',
            value: _date,
            onChanged: (DateTime? d) => setState(() => _date = d),
          ),
          const SizedBox(height: AppSpacing.lg),
          CustomButton(
            label: 'Simpan Transaksi',
            icon: AppIcons.check,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
