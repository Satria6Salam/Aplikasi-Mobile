import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/savings_models.dart';
import '../../data/repositories/savings_repository.dart';
import '../../services/cash_flow_service.dart';
import '../../services/savings_planner.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/savings_viewmodel.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/custom_button.dart';
import '../widgets/empty_state.dart';
import '../widgets/message_banner.dart';
import '../widgets/sheet_frame.dart';
import 'savings_sheets.dart';

/// Target tabungan: progres, kebutuhan per bulan, dan penilaian apakah
/// target realistis dibanding sisa uang bulan ini.
class SavingsScreen extends StatelessWidget {
  const SavingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SavingsViewModel>(
      create: (BuildContext context) => SavingsViewModel(
        authViewModel: context.read<AuthViewModel>(),
        savingsRepository: context.read<SavingsRepository>(),
        cashFlowService: context.read<CashFlowService>(),
      ),
      child: const _SavingsView(),
    );
  }
}

class _SavingsView extends StatefulWidget {
  const _SavingsView();

  @override
  State<_SavingsView> createState() => _SavingsViewState();
}

class _SavingsViewState extends State<_SavingsView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(context.read<SavingsViewModel>().load());
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addGoal() async {
    final SavingsViewModel vm = context.read<SavingsViewModel>();
    final GoalInput? input = await showGoalEditor(context);
    if (input == null || !mounted) return;
    final bool ok = await vm.addGoal(
      name: input.name,
      targetAmount: input.targetAmount,
      deadline: input.deadline,
      notes: input.notes,
    );
    if (mounted) _snack(ok ? 'Target dibuat.' : vm.errorMessage ?? 'Gagal.');
  }

  Future<void> _deposit(GoalProgress g, {bool withdraw = false}) async {
    final SavingsViewModel vm = context.read<SavingsViewModel>();
    final DepositInput? input = await showDepositSheet(
      context,
      goal: g.goal,
      withdraw: withdraw,
      suggestion: g.requiredPerMonth,
    );
    if (input == null || !mounted) return;
    final bool ok = withdraw
        ? await vm.withdraw(g.goal,
            amount: input.amount, date: input.date, notes: input.notes)
        : await vm.deposit(g.goal,
            amount: input.amount, date: input.date, notes: input.notes);
    if (!mounted) return;
    _snack(ok
        ? (withdraw ? 'Penarikan dicatat.' : 'Setoran dicatat.')
        : vm.errorMessage ?? 'Gagal.');
  }

  Future<void> _open(GoalProgress g) async {
    final SavingsViewModel vm = context.read<SavingsViewModel>();
    await showAppSheet<void>(
      context,
      (BuildContext _) => _GoalDetailSheet(vm: vm, goalId: g.goal.id!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SavingsViewModel vm = context.watch<SavingsViewModel>();
    final TextTheme textTheme = Theme.of(context).textTheme;

    Widget body;
    if (vm.isLoading && vm.goals.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (vm.goals.isEmpty) {
      body = ListView(
        children: [
          if (vm.errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: MessageBanner(message: vm.errorMessage!),
            ),
          EmptyState(
            icon: AppIcons.piggyBank,
            title: 'Belum ada target tabungan',
            message:
                'Tentukan sesuatu yang ingin dibeli, misalnya laptop Rp 8 juta dalam 6 bulan. Aplikasi menghitung berapa yang perlu disisihkan tiap bulan.',
            actionLabel: 'Buat Target',
            onAction: _addGoal,
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
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.piggyBank, color: AppColors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total tabungan',
                          style: textTheme.bodySmall
                              ?.copyWith(color: AppColors.white),
                        ),
                        Text(
                          AppFormatters.rupiah(vm.totalSaved),
                          style: AppTextStyles.amount(
                              size: 24, color: AppColors.white),
                        ),
                        if (vm.totalRequiredPerMonth > 0)
                          Text(
                            'Semua target butuh ${AppFormatters.rupiah(vm.totalRequiredPerMonth)} per bulan',
                            style: textTheme.bodySmall
                                ?.copyWith(color: AppColors.white),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _RealityBanner(vm: vm),
            for (final GoalProgress g in vm.goals)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: _GoalCard(
                  progress: g,
                  onOpen: () => _open(g),
                  onDeposit: () => _deposit(g),
                  onWithdraw: () => _deposit(g, withdraw: true),
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Target Tabungan')),
      body: SafeArea(child: body),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addGoal,
        backgroundColor: AppColors.emerald,
        foregroundColor: AppColors.white,
        icon: Icon(AppIcons.plus),
        label: const Text('Target Baru'),
      ),
    );
  }
}

/// Menilai apakah target realistis dibanding pemasukan - pengeluaran bulan ini.
class _RealityBanner extends StatelessWidget {
  const _RealityBanner({required this.vm});

  final SavingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    if (vm.activeGoals.every((GoalProgress g) => g.requiredPerMonth == null)) {
      return const SizedBox.shrink();
    }
    switch (vm.realityCheck) {
      case RealityCheck.realistic:
        return MessageBanner(
          message:
              'Sisa uang bulan ini sekitar ${AppFormatters.rupiah(vm.monthlyCapacity)}, '
              'cukup untuk kebutuhan menabung ${AppFormatters.rupiah(vm.totalRequiredPerMonth)}. '
              'Target Anda realistis.',
          type: BannerType.success,
        );
      case RealityCheck.shortfall:
        return MessageBanner(
          message:
              'Sisa uang bulan ini sekitar ${AppFormatters.rupiah(vm.monthlyCapacity < 0 ? 0 : vm.monthlyCapacity)}, '
              'sedangkan semua target butuh ${AppFormatters.rupiah(vm.totalRequiredPerMonth)} per bulan. '
              'Kurang sekitar ${AppFormatters.rupiah(vm.monthlyGap)}. '
              'Kurangi belanja atau perpanjang tenggat.',
          type: BannerType.warning,
        );
      case RealityCheck.unknown:
        return MessageBanner(
          message:
              'Catat pemasukan bulan ini agar aplikasi bisa menilai apakah target Anda realistis.',
          type: BannerType.warning,
          actionLabel: 'Catat Pemasukan',
          onAction: () => context.push(AppRoutes.incomes),
        );
    }
  }
}

String _statusLabel(GoalStatus s) => switch (s) {
      GoalStatus.completed => 'Tercapai',
      GoalStatus.ahead => 'Lebih cepat',
      GoalStatus.onTrack => 'Sesuai jadwal',
      GoalStatus.behind => 'Tertinggal',
      GoalStatus.overdue => 'Lewat tenggat',
      GoalStatus.noDeadline => 'Tanpa tenggat',
    };

({Color fg, Color bg}) _statusColors(GoalStatus s) => switch (s) {
      GoalStatus.completed || GoalStatus.ahead || GoalStatus.onTrack => (
          fg: AppColors.emeraldDeep,
          bg: AppColors.emeraldTint
        ),
      GoalStatus.behind => (
          fg: AppColors.warningDeep,
          bg: AppColors.warningTint
        ),
      GoalStatus.overdue => (fg: AppColors.error, bg: AppColors.errorTint),
      GoalStatus.noDeadline => (fg: AppColors.coolGray, bg: AppColors.border),
    };

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.progress,
    required this.onOpen,
    required this.onDeposit,
    required this.onWithdraw,
  });

  final GoalProgress progress;
  final VoidCallback onOpen;
  final VoidCallback onDeposit;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final SavingsGoalModel goal = progress.goal;
    final colors = _statusColors(progress.status);
    final DateTime? due = goal.deadline;

    return Container(
      decoration: AppDecorations.card(radius: AppRadius.cardLarge),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.cardLarge),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(goal.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.bg,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _statusLabel(progress.status),
                        style: textTheme.labelSmall?.copyWith(
                            color: colors.fg, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress.fraction,
                    minHeight: 10,
                    backgroundColor: AppColors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progress.status == GoalStatus.behind ||
                              progress.status == GoalStatus.overdue
                          ? AppColors.warning
                          : AppColors.emerald,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${AppFormatters.rupiah(goal.savedAmount)} dari ${AppFormatters.rupiah(goal.targetAmount)} '
                  '(${(progress.fraction * 100).floor()}%)',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                if (progress.status == GoalStatus.completed)
                  Text('Selamat, target tercapai!',
                      style: textTheme.bodySmall
                          ?.copyWith(color: AppColors.emeraldDeep))
                else ...[
                  Text(
                    due == null
                        ? 'Sisa ${AppFormatters.rupiah(goal.remaining)} · tanpa tenggat'
                        : 'Sisa ${AppFormatters.rupiah(goal.remaining)} · tenggat ${AppFormatters.longDate(due)}'
                            '${progress.status == GoalStatus.overdue ? '' : ' (${progress.monthsLeft} bulan lagi)'}',
                    style: textTheme.bodySmall,
                  ),
                  if (progress.requiredPerMonth != null &&
                      progress.status != GoalStatus.overdue)
                    Text(
                      'Perlu ${AppFormatters.rupiah(progress.requiredPerMonth!)} per bulan',
                      style: textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  if (progress.status == GoalStatus.behind)
                    Text(
                      'Kurang ${AppFormatters.rupiah(progress.shortfall)} dari jalur',
                      style: textTheme.bodySmall
                          ?.copyWith(color: AppColors.warningDeep),
                    ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: CustomButton(
                        label: 'Setor',
                        icon: AppIcons.plus,
                        onPressed: onDeposit,
                      ),
                    ),
                    if (goal.savedAmount > 0) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: CustomButton(
                          label: 'Tarik',
                          icon: AppIcons.minus,
                          variant: CustomButtonVariant.secondary,
                          onPressed: onWithdraw,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rincian target: riwayat setoran, ubah, dan hapus.
class _GoalDetailSheet extends StatefulWidget {
  const _GoalDetailSheet({required this.vm, required this.goalId});

  final SavingsViewModel vm;
  final int goalId;

  @override
  State<_GoalDetailSheet> createState() => _GoalDetailSheetState();
}

class _GoalDetailSheetState extends State<_GoalDetailSheet> {
  List<SavingsDepositModel> _deposits = <SavingsDepositModel>[];
  bool _loaded = false;

  GoalProgress? get _progress {
    for (final GoalProgress g in widget.vm.goals) {
      if (g.goal.id == widget.goalId) return g;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final GoalProgress? p = _progress;
    if (p == null) return;
    final List<SavingsDepositModel> list = await widget.vm.depositsOf(p.goal);
    if (!mounted) return;
    setState(() {
      _deposits = list;
      _loaded = true;
    });
  }

  Future<void> _edit(SavingsGoalModel goal) async {
    final GoalInput? input = await showGoalEditor(context, existing: goal);
    if (input == null || !mounted) return;
    await widget.vm.updateGoal(
      goal,
      name: input.name,
      targetAmount: input.targetAmount,
      deadline: input.deadline,
      notes: input.notes,
    );
    if (mounted) setState(() {});
  }

  Future<void> _delete(SavingsGoalModel goal) async {
    final bool ok = await showConfirmDialog(
      context,
      title: 'Hapus target?',
      message:
          'Target "${goal.name}" dan seluruh riwayat setorannya akan dihapus. '
          'Uang yang sudah tertabung kembali menjadi sisa uang bebas.',
      confirmLabel: 'Hapus',
      isDestructive: true,
    );
    if (!ok || !mounted) return;
    await widget.vm.deleteGoal(goal);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _deleteDeposit(SavingsDepositModel d) async {
    final bool ok = await showConfirmDialog(
      context,
      title: 'Hapus catatan ini?',
      message:
          '${d.isWithdrawal ? 'Penarikan' : 'Setoran'} ${AppFormatters.rupiah(d.amount.abs())} akan dihapus dan saldo target dihitung ulang.',
      confirmLabel: 'Hapus',
      isDestructive: true,
    );
    if (!ok) return;
    await widget.vm.deleteDeposit(d);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.vm,
      builder: (BuildContext context, Widget? _) {
        final GoalProgress? p = _progress;
        if (p == null) return const SizedBox.shrink();
        final TextTheme textTheme = Theme.of(context).textTheme;
        final SavingsGoalModel goal = p.goal;

        return SheetFrame(
          title: goal.name,
          subtitle:
              '${AppFormatters.rupiah(goal.savedAmount)} dari ${AppFormatters.rupiah(goal.targetAmount)}'
              '${(goal.notes ?? '').isEmpty ? '' : '\n${goal.notes}'}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Riwayat', style: textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              if (!_loaded)
                const Center(child: CircularProgressIndicator())
              else if (_deposits.isEmpty)
                Text('Belum ada setoran.', style: textTheme.bodySmall)
              else
                for (final SavingsDepositModel d in _deposits)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(AppFormatters.longDate(d.date),
                                  style: textTheme.bodyMedium),
                              if ((d.notes ?? '').isNotEmpty)
                                Text(d.notes!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodySmall),
                            ],
                          ),
                        ),
                        Text(
                          '${d.isWithdrawal ? '−' : '+'}${AppFormatters.rupiah(d.amount.abs())}',
                          style: AppTextStyles.amount(
                            size: 14,
                            color: d.isWithdrawal
                                ? AppColors.error
                                : AppColors.emeraldDeep,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Hapus catatan',
                          icon: Icon(AppIcons.trash, size: 18),
                          onPressed: () => _deleteDeposit(d),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: AppSpacing.md),
              CustomButton(
                label: 'Ubah target',
                icon: AppIcons.pencil,
                variant: CustomButtonVariant.secondary,
                onPressed: () => _edit(goal),
              ),
              const SizedBox(height: 8),
              CustomButton(
                label: 'Hapus target',
                icon: AppIcons.trash,
                variant: CustomButtonVariant.danger,
                onPressed: () => _delete(goal),
              ),
            ],
          ),
        );
      },
    );
  }
}
