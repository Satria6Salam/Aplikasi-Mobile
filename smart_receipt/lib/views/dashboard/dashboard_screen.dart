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
import '../../data/models/category_summary_model.dart';
import '../../data/models/transaction_model.dart';
import '../../services/insight_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/dashboard_viewmodel.dart';
import '../widgets/cash_flow_card.dart';
import '../widgets/category_mini_list.dart';
import '../widgets/custom_button.dart';
import '../widgets/dashboard_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/insight_card.dart';
import '../widgets/message_banner.dart';
import '../widgets/period_search_sheet.dart';
import '../widgets/period_selector.dart';
import '../widgets/qris_pending_banner.dart';
import '../widgets/quick_actions.dart';
import '../widgets/summary_card.dart';
import '../widgets/theme_illustrations.dart';
import '../widgets/transaction_card.dart';
import '../widgets/transaction_detail_sheet.dart';

/// Menu Beranda: ringkasan periode, angka penting, rekap singkat kategori,
/// satu wawasan utama, dan transaksi terbaru. Rincian ada di menu lain.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static const int _recentCount = 5;

  Duration _delay(int step) => Duration(milliseconds: 70 * step);

  String _compareLabel(PeriodMode mode) {
    switch (mode) {
      case PeriodMode.day:
        return 'hari sebelumnya';
      case PeriodMode.month:
        return 'bulan lalu';
      case PeriodMode.year:
        return 'tahun lalu';
    }
  }

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel dash = context.watch<DashboardViewModel>();
    final AuthViewModel auth = context.watch<AuthViewModel>();
    final SpendingAnalytics analytics = dash.analytics;
    final DashboardPeriod period = dash.period;
    final String? error = dash.errorMessage;
    final String periodLabel = AppFormatters.period(period);
    final List<TransactionModel> recent =
        dash.transactions.take(_recentCount).toList();
    final bool hasData = analytics.hasData && !dash.isEmpty;
    final TransactionModel? biggest = analytics.biggestTransaction;
    final bool isDay = period.mode == PeriodMode.day;
    final bool canProject = analytics.isCurrentPeriod && !isDay;
    final Insight? topInsight =
        analytics.insights.isEmpty ? null : analytics.insights.first;

    void openCategory(CategorySummaryModel summary) {
      dash.setCategoryFilter(<int>{summary.categoryId});
      context.go(AppRoutes.history);
    }

    return Scaffold(
      body: SafeArea(
        child: CashFlowScope(
          child: RefreshIndicator(
            color: AppColors.emerald,
            onRefresh: dash.refresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    0,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: FadeSlideIn(
                      child: DashboardHeader(
                        name: auth.currentUser?.name ?? '',
                        onSettingsTap: () => context.go(AppRoutes.settings),
                        onNotificationTap: () =>
                            context.push(AppRoutes.notifications),
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: SizedBox(
                      height: 3,
                      child: dash.isLoading
                          ? const LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: Colors.transparent,
                            )
                          : null,
                    ),
                  ),
                ),
                SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      const SizedBox(height: AppSpacing.sm),
                      FadeSlideIn(
                        delay: _delay(1),
                        child: PeriodSelector(
                          period: period,
                          canGoNext: dash.canGoNext,
                          onPrevious: dash.goToPrevious,
                          onNext: dash.goToNext,
                          onSearch: () => showPeriodSearchSheet(context),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FadeSlideIn(
                        delay: _delay(2),
                        child: SummaryCard(
                          periodLabel: periodLabel,
                          totalAmount: dash.total,
                          transactionCount: dash.transactionCount,
                          averagePerDay: analytics.averagePerDay,
                          projectedTotal: analytics.projectedTotal,
                          isCurrentPeriod: canProject,
                          compareLabel: _compareLabel(period.mode),
                          changePercent: analytics.changePercent,
                          topCategoryName: dash.topCategory?.categoryName,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FadeSlideIn(
                        delay: _delay(3),
                        child: QuickActionsRow(
                          actions: [
                            QuickAction(
                              icon: AppIcons.scanLine,
                              label: 'Scan Struk',
                              highlight: true,
                              onTap: () => context.push(AppRoutes.scan),
                            ),
                            QuickAction(
                              icon: AppIcons.qrCode,
                              label: 'Scan QRIS',
                              onTap: () => context.push(AppRoutes.qris),
                            ),
                            QuickAction(
                              icon: AppIcons.penLine,
                              label: 'Catat Manual',
                              onTap: () => context.push(AppRoutes.manualEntry),
                            ),
                            QuickAction(
                              icon: AppIcons.wallet,
                              label: 'Pemasukan',
                              onTap: () => context.push(AppRoutes.incomes),
                            ),
                          ],
                        ),
                      ),
                      const QrisPendingBanner(),
                      if (error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        MessageBanner(
                          message: error,
                          actionLabel: 'Coba lagi',
                          onAction: dash.refresh,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      FadeSlideIn(
                        delay: _delay(4),
                        child: const CashFlowBalanceCard(),
                      ),
                      if (hasData) ...[
                        const SizedBox(height: AppSpacing.lg),
                        FadeSlideIn(
                          delay: _delay(5),
                          child: _SectionHeader(
                            title: 'Pengeluaran per Kategori',
                            subtitle:
                                'Ketuk kategori untuk melihat transaksinya',
                            actionLabel: 'Analisis',
                            onAction: () => context.push(AppRoutes.analysis),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        FadeSlideIn(
                          delay: _delay(6),
                          child: CategoryMiniList(
                            summaries: dash.categorySummaries,
                            percentageOf: dash.percentageOf,
                            onSelect: openCategory,
                          ),
                        ),
                      ],
                      const CashFlowTrendCard(),
                      if (hasData && topInsight != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        FadeSlideIn(
                          delay: _delay(7),
                          child: _SectionHeader(
                            title: 'Saran untuk Anda',
                            subtitle: 'Berdasarkan pola belanja periode ini',
                            actionLabel: 'Lainnya',
                            onAction: () => context.push(AppRoutes.analysis),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        FadeSlideIn(
                          delay: _delay(8),
                          child: InsightCard(insight: topInsight),
                        ),
                      ],
                      if (hasData) ...[
                        const SizedBox(height: AppSpacing.lg),
                        FadeSlideIn(
                          delay: _delay(9),
                          child: const _SectionHeader(
                            title: 'Statistik Periode',
                            subtitle: 'Angka penting pengeluaran Anda',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        FadeSlideIn(
                          delay: _delay(9),
                          child: _PeriodStats(
                            rows: <_StatRowData>[
                              _StatRowData(
                                icon: AppIcons.banknote,
                                label: 'Rata-rata per transaksi',
                                value: AppFormatters.rupiah(
                                    analytics.averagePerTransaction),
                                note: '${analytics.transactionCount} transaksi',
                              ),
                              _StatRowData(
                                icon: AppIcons.crown,
                                label: 'Transaksi terbesar',
                                value: AppFormatters.rupiah(
                                    biggest?.totalAmount ?? 0),
                                note: biggest?.merchantName,
                              ),
                              _StatRowData(
                                icon: AppIcons.calendarDays,
                                label: 'Hari ada pengeluaran',
                                value:
                                    '${analytics.activeDays} dari ${analytics.daysElapsed} hari',
                              ),
                              _StatRowData(
                                icon: canProject
                                    ? AppIcons.trendingUp
                                    : AppIcons.wallet,
                                label: canProject
                                    ? (period.mode == PeriodMode.year
                                        ? 'Perkiraan akhir tahun'
                                        : 'Perkiraan akhir bulan')
                                    : 'Periode sebelumnya',
                                value: AppFormatters.rupiah(canProject
                                    ? analytics.projectedTotal
                                    : analytics.previousMonthTotal),
                                note: canProject
                                    ? 'jika pola berlanjut'
                                    : 'total ${_compareLabel(period.mode)}',
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      FadeSlideIn(
                        delay: _delay(10),
                        child: _SectionHeader(
                          title: 'Transaksi Terbaru',
                          subtitle: 'Lima catatan terakhir pada periode ini',
                          actionLabel: dash.isEmpty ? null : 'Lihat semua',
                          onAction: () => context.go(AppRoutes.history),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ]),
                  ),
                ),
                if (dash.isEmpty)
                  SliverToBoxAdapter(
                    child: FadeSlideIn(
                      child: Column(
                        children: [
                          EmptyState(
                            art: ThemeArtKind.scan,
                            icon: AppIcons.receipt,
                            title: 'Belum ada transaksi',
                            message:
                                'Tidak ada pengeluaran tercatat pada $periodLabel. Pindai struk untuk mulai mencatat, atau gunakan tombol cari untuk melihat periode lain.',
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xl,
                            ),
                            child: CustomButton(
                              label: 'Scan Struk',
                              icon: AppIcons.scanLine,
                              onPressed: () => context.push(AppRoutes.scan),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (BuildContext context, int index) {
                          final TransactionModel transaction = recent[index];
                          return FadeSlideIn(
                            delay: Duration(milliseconds: 40 * index),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: TransactionCard(
                                transaction: transaction,
                                extraCategories:
                                    dash.categoryCountOf(transaction) - 1,
                                onTap: () => showTransactionDetailSheet(
                                  context,
                                  transaction,
                                ),
                              ),
                            ),
                          );
                        },
                        childCount: recent.length,
                      ),
                    ),
                  ),
                if (!dash.isEmpty && dash.transactionCount > _recentCount)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: CustomButton(
                        label: 'Lihat semua ${dash.transactionCount} transaksi',
                        variant: CustomButtonVariant.secondary,
                        onPressed: () => context.go(AppRoutes.history),
                      ),
                    ),
                  ),
                const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.lg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: textTheme.titleLarge),
              if (subtitle != null) Text(subtitle!, style: textTheme.bodySmall),
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel ?? '')),
      ],
    );
  }
}

/// Satu baris angka pada kartu statistik.
class _StatRowData {
  const _StatRowData({
    required this.icon,
    required this.label,
    required this.value,
    this.note,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? note;
}

/// Statistik periode dalam satu kartu rapi: label di kiri, angka di kanan.
class _PeriodStats extends StatelessWidget {
  const _PeriodStats({required this.rows});

  final List<_StatRowData> rows;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: AppDecorations.card(radius: AppRadius.cardLarge),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.emeraldTint,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Icon(rows[i].icon,
                        size: 18, color: AppColors.emeraldDeep),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rows[i].label, style: textTheme.bodyMedium),
                        if (rows[i].note != null)
                          Text(
                            rows[i].note!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      rows[i].value,
                      textAlign: TextAlign.right,
                      style: AppTextStyles.amount(size: 15),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
