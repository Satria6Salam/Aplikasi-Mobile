import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/dashboard_period.dart';
import '../../core/utils/formatters.dart';
import '../../services/cash_flow_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/cash_flow_viewmodel.dart';
import '../../viewmodels/dashboard_viewmodel.dart';
import 'price_line_chart.dart';

/// Memuat arus kas untuk periode yang sedang dilihat di Dasbor dan
/// membagikannya ke [CashFlowBalanceCard] dan [CashFlowTrendCard].
///
/// Memuat ulang sendiri saat periode atau total pengeluaran di Dasbor berubah
/// (mis. setelah memindai struk).
class CashFlowScope extends StatefulWidget {
  const CashFlowScope({super.key, required this.child});

  final Widget child;

  @override
  State<CashFlowScope> createState() => _CashFlowScopeState();
}

class _CashFlowScopeState extends State<CashFlowScope> {
  late final CashFlowViewModel _vm = CashFlowViewModel(
    authViewModel: context.read<AuthViewModel>(),
    service: context.read<CashFlowService>(),
  );
  String? _loadedKey;

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel dash = context.watch<DashboardViewModel>();
    final DashboardPeriod period = dash.period;
    final String key =
        '${period.mode.name}-${period.anchor.toIso8601String()}-${dash.total}-${dash.transactionCount}';

    // Muat ulang setelah frame ini selesai (tidak boleh saat build).
    if (!dash.isLoading && key != _loadedKey) {
      _loadedKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_vm.load(period));
      });
    }
    return ChangeNotifierProvider<CashFlowViewModel>.value(
      value: _vm,
      child: widget.child,
    );
  }
}

/// Kartu "Pemasukan & Sisa Uang": uang masuk, uang keluar, dan uang yang
/// ditabung, lalu hasilnya, yaitu sisa uang bebas. Ketiganya ditampilkan agar
/// rumus "pemasukan − pengeluaran − tabungan" bisa dicek langsung.
class CashFlowBalanceCard extends StatelessWidget {
  const CashFlowBalanceCard({super.key});

  Future<void> _open(BuildContext context, String route) async {
    final CashFlowViewModel vm = context.read<CashFlowViewModel>();
    await context.push(route);
    await vm.reload();
  }

  @override
  Widget build(BuildContext context) {
    final CashFlowViewModel vm = context.watch<CashFlowViewModel>();
    final DashboardPeriod period = context.watch<DashboardViewModel>().period;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final CashFlow flow = vm.flow;
    final bool noIncome = flow.income <= 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppDecorations.card(radius: AppRadius.cardLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.wallet, size: 20, color: AppColors.emerald),
              const SizedBox(width: 8),
              Expanded(
                child:
                    Text('Pemasukan & Sisa Uang', style: textTheme.titleMedium),
              ),
              if (vm.isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(AppFormatters.period(period), style: textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          _FreeBalance(flow: flow),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _Figure(
                  label: 'Pemasukan',
                  value: flow.income,
                  color: AppColors.emeraldDeep,
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Pengeluaran',
                  value: flow.expense,
                  color: AppColors.error,
                ),
              ),
              Expanded(
                child: _Figure(
                  label: 'Ditabung',
                  value: flow.saved,
                  color: AppColors.warningDeep,
                ),
              ),
            ],
          ),
          if (noIncome) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Belum ada pemasukan pada periode ini. Catat pemasukan agar sisa uang Anda bisa dihitung.',
              style: textTheme.bodySmall,
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: flow.spentRatio.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(
                  flow.spentRatio > 1 ? AppColors.error : AppColors.emerald,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Dibelanjakan ${AppFormatters.percent(flow.spentRatio)} dari pemasukan',
              style: textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _open(context, AppRoutes.incomes),
                  icon: Icon(AppIcons.plus, size: 18),
                  label: const Text('Pemasukan'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _open(context, AppRoutes.savings),
                  icon: Icon(AppIcons.piggyBank, size: 18),
                  label: const Text('Tabungan'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Grafik 6 bulan pemasukan dan pengeluaran. Tidak tampil bila belum ada data.
class CashFlowTrendCard extends StatelessWidget {
  const CashFlowTrendCard({super.key});

  @override
  Widget build(BuildContext context) {
    final CashFlowViewModel vm = context.watch<CashFlowViewModel>();
    if (!vm.trend.any((MonthCashFlow m) => m.flow.hasData)) {
      return const SizedBox.shrink();
    }
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: AppDecorations.card(radius: AppRadius.cardLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pemasukan vs Pengeluaran', style: textTheme.titleMedium),
            const SizedBox(height: 2),
            Text('6 bulan terakhir', style: textTheme.bodySmall),
            const SizedBox(height: AppSpacing.md),
            CashFlowChart(months: vm.trend),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Legend(color: AppColors.emerald, label: 'Pemasukan'),
                const SizedBox(width: 16),
                _Legend(color: AppColors.error, label: 'Pengeluaran'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Sisa uang bebas, ditonjolkan; merah bila defisit.
class _FreeBalance extends StatelessWidget {
  const _FreeBalance({required this.flow});

  final CashFlow flow;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool deficit = flow.isDeficit;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: deficit ? AppColors.errorTint : AppColors.emeraldTint,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Sisa uang bebas', style: textTheme.bodySmall),
              if (deficit) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Defisit',
                    style: textTheme.labelSmall?.copyWith(
                        color: AppColors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              AppFormatters.rupiah(flow.free),
              style: AppTextStyles.amount(
                size: 26,
                color: deficit ? AppColors.error : AppColors.emeraldDeep,
              ),
            ),
          ),
          Text(
            'Pemasukan − pengeluaran − tabungan',
            style: textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.labelSmall),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            AppFormatters.rupiah(value),
            style: AppTextStyles.amount(size: 14, color: color),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// Grafik batang berdampingan: pemasukan (hijau) dan pengeluaran (merah)
/// per bulan.
class CashFlowChart extends StatelessWidget {
  const CashFlowChart({super.key, required this.months, this.height = 150});

  final List<MonthCashFlow> months;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _CashFlowChartPainter(
          months: months,
          labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.coolGray,
                    fontSize: 10,
                  ) ??
              const TextStyle(fontSize: 10, color: AppColors.coolGray),
        ),
      ),
    );
  }
}

class _CashFlowChartPainter extends CustomPainter {
  _CashFlowChartPainter({required this.months, required this.labelStyle});

  final List<MonthCashFlow> months;
  final TextStyle labelStyle;

  static const double _left = 40;
  static const double _bottom = 20;
  static const double _top = 6;

  TextPainter _text(String text) => TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;
    final Rect area =
        Rect.fromLTRB(_left, _top, size.width - 4, size.height - _bottom);

    double maxValue = 0;
    for (final MonthCashFlow m in months) {
      if (m.flow.income > maxValue) maxValue = m.flow.income;
      if (m.flow.expense > maxValue) maxValue = m.flow.expense;
    }
    if (maxValue <= 0) maxValue = 1;

    final Paint grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (int i = 0; i <= 2; i++) {
      final double y = area.top + area.height * i / 2;
      canvas.drawLine(Offset(area.left, y), Offset(area.right, y), grid);
      final TextPainter label =
          _text(PriceLineChart.compact(maxValue * (1 - i / 2)));
      label.paint(
          canvas, Offset(area.left - label.width - 6, y - label.height / 2));
    }

    final double slot = area.width / months.length;
    final double barWidth = (slot * 0.28).clamp(4.0, 18.0);
    for (int i = 0; i < months.length; i++) {
      final double center = area.left + slot * (i + 0.5);
      void bar(double value, double dx, Color color) {
        if (value <= 0) return;
        final double h = area.height * (value / maxValue);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTWH(center + dx, area.bottom - h, barWidth, h),
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          ),
          Paint()..color = color,
        );
      }

      bar(months[i].flow.income, -barWidth - 1, AppColors.emerald);
      bar(months[i].flow.expense, 1, AppColors.error);

      final TextPainter name =
          _text(AppFormatters.monthShort(months[i].month.month));
      name.paint(canvas,
          Offset(center - name.width / 2, size.height - name.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant _CashFlowChartPainter old) =>
      old.months != months || old.labelStyle != labelStyle;
}
