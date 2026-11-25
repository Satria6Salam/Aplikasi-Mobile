import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../core/utils/dashboard_period.dart';
import '../../core/utils/formatters.dart';

/// Pemilih periode Dasbor: panah sebelumnya/berikutnya, label periode,
/// dan tombol cari untuk melompat ke tanggal, bulan, atau tahun tertentu.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.period,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.onSearch,
    this.onDark = false,
  });

  final DashboardPeriod period;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSearch;

  /// True di atas latar hijau gelap.
  final bool onDark;

  String get _caption {
    switch (period.mode) {
      case PeriodMode.day:
        return 'Harian';
      case PeriodMode.month:
        return 'Bulanan';
      case PeriodMode.year:
        return 'Tahunan';
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final String label = AppFormatters.period(period);
    final Color fg = onDark ? AppColors.white : AppColors.slateDark;
    final Color accent =
        onDark ? AppColors.emeraldLight : AppColors.emeraldDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: onDark ? AppDecorations.glass() : AppDecorations.card(),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Periode sebelumnya',
            onPressed: onPrevious,
            icon: Icon(AppIcons.chevronLeft, color: fg),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.control),
              onTap: onSearch,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    return FadeTransition(opacity: animation, child: child);
                  },
                  child: Column(
                    key: ValueKey<String>('$_caption-$label'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _caption,
                        style: textTheme.labelMedium?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(color: fg),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cari periode',
            onPressed: onSearch,
            icon: Icon(AppIcons.search, color: accent),
          ),
          IconButton(
            tooltip: 'Periode berikutnya',
            onPressed: canGoNext ? onNext : null,
            icon: Icon(
              AppIcons.chevronRight,
              color: canGoNext ? fg : fg.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}
