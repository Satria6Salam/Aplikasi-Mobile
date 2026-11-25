import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import 'animated_counter.dart';
import 'mascot.dart';
import 'shimmer_sweep.dart';

/// Kartu utama Dasbor: total bulan ini (animasi hitung), perbandingan dengan
/// bulan lalu, dan tiga angka penting.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.periodLabel,
    required this.totalAmount,
    required this.transactionCount,
    required this.averagePerDay,
    required this.projectedTotal,
    required this.isCurrentPeriod,
    this.compareLabel = 'periode lalu',
    this.changePercent,
    this.topCategoryName,
  });

  final String periodLabel;
  final double totalAmount;
  final int transactionCount;
  final double averagePerDay;
  final double projectedTotal;
  final bool isCurrentPeriod;

  /// Pembanding pada lencana perubahan (mis. "bulan lalu", "tahun lalu").
  final String compareLabel;

  /// Perubahan (%) dibanding periode yang sama bulan lalu (null bila tak ada pembanding).
  final double? changePercent;
  final String? topCategoryName;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final double? change = changePercent;

    return Container(
      width: double.infinity,
      decoration: AppDecorations.glass(radius: 28),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const ShimmerSweep(radius: 28),
          // Kilau lembut di sudut kanan atas.
          Positioned(
            right: -50,
            top: -60,
            child: Container(
              width: 170,
              height: 170,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x1F34C38A),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Total Pengeluaran $periodLabel',
                        style: textTheme.bodyMedium?.copyWith(
                          color: const Color(0xCCFFFFFF),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Mascot(
                        kind: MascotKind.receipt, height: 44, float: true),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AnimatedCounter(
                    value: totalAmount,
                    formatter: AppFormatters.rupiah,
                    style:
                        AppTextStyles.amount(size: 38, color: AppColors.white),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (change != null)
                      _Pill(
                        icon: change >= 0
                            ? AppIcons.trendingUp
                            : AppIcons.trendingDown,
                        text:
                            '${change >= 0 ? 'Naik' : 'Turun'} ${change.abs().round()}% dari $compareLabel',
                      ),
                    if (topCategoryName != null)
                      _Pill(
                        icon: AppIcons.crown,
                        text: 'Terbesar: $topCategoryName',
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0x26000000),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Row(
                    children: [
                      _Mini(
                        label: 'Transaksi',
                        value: AnimatedCounter(
                          value: transactionCount.toDouble(),
                          formatter: (double v) => v.round().toString(),
                          style: _miniStyle(textTheme),
                        ),
                      ),
                      const _Divider(),
                      _Mini(
                        label: 'Rata-rata/hari',
                        value: AnimatedCounter(
                          value: averagePerDay,
                          formatter: _compact,
                          style: _miniStyle(textTheme),
                        ),
                      ),
                      const _Divider(),
                      _Mini(
                        label: isCurrentPeriod ? 'Proyeksi' : 'Total',
                        value: AnimatedCounter(
                          value: isCurrentPeriod ? projectedTotal : totalAmount,
                          formatter: _compact,
                          style: _miniStyle(textTheme),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle? _miniStyle(TextTheme textTheme) {
    return textTheme.titleMedium?.copyWith(color: AppColors.white);
  }

  /// Format ringkas agar muat pada kartu kecil: 1,2 jt / 85 rb.
  static String _compact(double value) {
    if (value >= 1000000) {
      return 'Rp${(value / 1000000).toStringAsFixed(1).replaceAll('.', ',')} jt';
    }
    if (value >= 1000) return 'Rp${(value / 1000).round()} rb';
    return 'Rp${value.round()}';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x33FFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.white),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: value),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: const Color(0xCCFFFFFF),
                ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 28, color: const Color(0x33FFFFFF));
  }
}
