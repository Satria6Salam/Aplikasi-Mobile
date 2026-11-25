import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/month_utils.dart';
import '../../data/models/income_model.dart';
import '../../data/repositories/income_repository.dart';
import '../../data/repositories/savings_repository.dart';
import '../../services/income_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/income_viewmodel.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/empty_state.dart';
import '../widgets/message_banner.dart';
import 'allocation_sheet.dart';
import 'income_editor_sheet.dart';

/// Pemasukan: daftar per bulan, pemasukan berulang, dan penyisihan ke tabungan.
class IncomeScreen extends StatelessWidget {
  const IncomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<IncomeViewModel>(
      create: (BuildContext context) => IncomeViewModel(
        authViewModel: context.read<AuthViewModel>(),
        incomeRepository: context.read<IncomeRepository>(),
        savingsRepository: context.read<SavingsRepository>(),
        incomeService: context.read<IncomeService>(),
      ),
      child: const _IncomeView(),
    );
  }
}

class _IncomeView extends StatefulWidget {
  const _IncomeView();

  @override
  State<_IncomeView> createState() => _IncomeViewState();
}

class _IncomeViewState extends State<_IncomeView> {
  @override
  void initState() {
    super.initState();
    // load() memberi tahu pendengar, jadi tidak boleh dipanggil saat build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(context.read<IncomeViewModel>().load());
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add() async {
    final IncomeViewModel vm = context.read<IncomeViewModel>();
    final IncomeEditorResult? r =
        await showIncomeEditor(context, goals: vm.activeGoals);
    if (r == null || !mounted) return;

    if (r.recurring) {
      final RecurringCreated? created = await vm.addRecurring(
        source: r.source,
        amount: r.amount,
        startDate: r.date,
        notes: r.notes,
        autoGoalId: r.autoGoalId,
        autoAmount: r.autoAmount,
      );
      if (!mounted) return;
      if (created == null) {
        _snack(vm.errorMessage ?? 'Gagal menyimpan pemasukan berulang.');
        return;
      }
      _snack('Pemasukan berulang tersimpan'
          '${created.created.isEmpty ? '' : ' (${created.created.length} pemasukan dicatat)'}.');
      // Tanpa setoran otomatis, tawarkan penyisihan untuk pemasukan terbaru.
      if (r.autoGoalId == null && created.created.isNotEmpty) {
        await _offerAllocation(created.created.last);
      }
      return;
    }

    final IncomeModel? saved = await vm.addIncome(
      source: r.source,
      amount: r.amount,
      date: r.date,
      notes: r.notes,
    );
    if (!mounted) return;
    if (saved == null) {
      _snack(vm.errorMessage ?? 'Gagal menyimpan pemasukan.');
      return;
    }
    _snack('Pemasukan ${AppFormatters.rupiah(saved.amount)} tersimpan.');
    await _offerAllocation(saved);
  }

  /// Pilihan C: tawarkan penyisihan ke target tepat saat uang masuk.
  Future<void> _offerAllocation(IncomeModel income) async {
    final IncomeViewModel vm = context.read<IncomeViewModel>();
    final goals = vm.activeGoals;
    if (goals.isEmpty) return;

    final Map<int, double>? chosen = await showAllocationSheet(
      context,
      income: income,
      goals: goals,
      suggestions: vm.suggestAllocation(income.amount),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;

    final bool ok = await vm.allocate(income, chosen);
    if (!mounted) return;
    if (!ok) {
      _snack(vm.errorMessage ?? 'Gagal menyisihkan ke tabungan.');
      return;
    }
    final double total =
        chosen.values.fold<double>(0, (double a, double b) => a + b);
    _snack('${AppFormatters.rupiah(total)} disisihkan ke tabungan.');
  }

  Future<void> _edit(IncomeModel income) async {
    final IncomeViewModel vm = context.read<IncomeViewModel>();
    final IncomeEditorResult? r =
        await showIncomeEditor(context, existing: income);
    if (r == null || !mounted) return;

    if (r.delete) {
      final bool ok = await vm.deleteIncome(income);
      if (mounted) {
        _snack(
            ok ? 'Pemasukan dihapus.' : vm.errorMessage ?? 'Gagal menghapus.');
      }
      return;
    }
    final bool ok = await vm.updateIncome(
      income,
      source: r.source,
      amount: r.amount,
      date: r.date,
      notes: r.notes,
    );
    if (mounted && !ok) _snack(vm.errorMessage ?? 'Gagal mengubah pemasukan.');
  }

  Future<void> _deleteRecurring(RecurringIncomeModel rec) async {
    final IncomeViewModel vm = context.read<IncomeViewModel>();
    final bool ok = await showConfirmDialog(
      context,
      title: 'Hapus pemasukan berulang?',
      message:
          'Pemasukan ${rec.source} tidak akan dicatat lagi tiap bulan. Yang sudah tercatat tetap ada.',
      confirmLabel: 'Hapus',
      isDestructive: true,
    );
    if (ok) await vm.deleteRecurring(rec);
  }

  @override
  Widget build(BuildContext context) {
    final IncomeViewModel vm = context.watch<IncomeViewModel>();
    final TextTheme textTheme = Theme.of(context).textTheme;
    final DateTime now = DateTime.now();

    final Map<String, List<IncomeModel>> byMonth =
        <String, List<IncomeModel>>{};
    for (final IncomeModel i in vm.incomes) {
      byMonth.putIfAbsent(MonthUtils.key(i.date), () => <IncomeModel>[]).add(i);
    }

    Widget body;
    if (vm.isLoading && vm.incomes.isEmpty && vm.recurring.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (vm.incomes.isEmpty && vm.recurring.isEmpty) {
      body = ListView(
        children: [
          if (vm.errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: MessageBanner(message: vm.errorMessage!),
            ),
          EmptyState(
            icon: AppIcons.wallet,
            title: 'Belum ada pemasukan',
            message:
                'Catat uang saku, gaji, atau penghasilan lain agar aplikasi bisa menghitung sisa uang Anda tiap bulan.',
            actionLabel: 'Catat Pemasukan',
            onAction: _add,
          ),
        ],
      );
    } else {
      body = RefreshIndicator(
        color: AppColors.emerald,
        onRefresh: vm.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 96),
          children: [
            if (vm.errorMessage != null) ...[
              MessageBanner(message: vm.errorMessage!),
              const SizedBox(height: AppSpacing.md),
            ],
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.emeraldTint,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.wallet, color: AppColors.emeraldDeep),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pemasukan ${AppFormatters.monthYear(now)}',
                            style: textTheme.bodySmall),
                        Text(
                          AppFormatters.rupiah(vm.totalInMonth(now)),
                          style: AppTextStyles.amount(
                              size: 22, color: AppColors.emeraldDeep),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (vm.recurring.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text('Pemasukan berulang', style: textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              for (final RecurringIncomeModel rec in vm.recurring)
                _RecurringTile(
                  rec: rec,
                  goalName: rec.autoGoalId == null
                      ? null
                      : vm.goalNameOf(rec.autoGoalId!),
                  onToggle: (bool v) => vm.setRecurringActive(rec, v),
                  onDelete: () => _deleteRecurring(rec),
                ),
            ],
            for (final MapEntry<String, List<IncomeModel>> entry
                in byMonth.entries) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      AppFormatters.monthYear(MonthUtils.parse(entry.key)),
                      style: textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    AppFormatters.rupiah(entry.value.fold<double>(
                        0, (double s, IncomeModel i) => s + i.amount)),
                    style: AppTextStyles.amount(
                        size: 14, color: AppColors.emeraldDeep),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final IncomeModel income in entry.value)
                _IncomeTile(income: income, onTap: () => _edit(income)),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pemasukan')),
      body: SafeArea(child: body),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: AppColors.emerald,
        foregroundColor: AppColors.white,
        icon: Icon(AppIcons.plus),
        label: const Text('Catat Pemasukan'),
      ),
    );
  }
}

class _IncomeTile extends StatelessWidget {
  const _IncomeTile({required this.income, required this.onTap});

  final IncomeModel income;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: AppDecorations.card(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.mint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(AppIcons.trendingUp,
                        size: 20, color: AppColors.emerald),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(income.source,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.titleSmall),
                            ),
                            if (income.isAutomatic) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.border,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text('Otomatis',
                                    style: textTheme.labelSmall),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          AppFormatters.longDate(income.date) +
                              ((income.notes ?? '').isEmpty
                                  ? ''
                                  : ' · ${income.notes}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '+${AppFormatters.rupiah(income.amount)}',
                    style: AppTextStyles.amount(
                        size: 15, color: AppColors.emeraldDeep),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecurringTile extends StatelessWidget {
  const _RecurringTile({
    required this.rec,
    required this.goalName,
    required this.onToggle,
    required this.onDelete,
  });

  final RecurringIncomeModel rec;
  final String? goalName;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, 4, 8),
        decoration: AppDecorations.card(),
        child: Row(
          children: [
            Icon(AppIcons.repeat, size: 20, color: AppColors.emerald),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${rec.source} · ${AppFormatters.rupiah(rec.amount)}',
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall,
                  ),
                  Text(
                    'Tiap tanggal ${rec.dayOfMonth}'
                    '${rec.hasAutoAllocation ? ' · ${goalName == null ? 'target dihapus' : '→ $goalName'} ${AppFormatters.rupiah(rec.autoAmount!)}' : ''}',
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Switch(
              value: rec.isActive,
              activeThumbColor: AppColors.emerald,
              onChanged: onToggle,
            ),
            IconButton(
              tooltip: 'Hapus',
              icon: Icon(AppIcons.trash, size: 20),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
