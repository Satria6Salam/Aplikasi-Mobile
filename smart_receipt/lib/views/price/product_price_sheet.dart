import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/purchase_record_model.dart';
import '../../services/price_comparison_service.dart';
import '../../viewmodels/price_comparison_viewmodel.dart';
import '../widgets/price_line_chart.dart';

/// Rincian harga sebuah barang: statistik, grafik, perbandingan antar toko,
/// dan riwayat pembelian.
Future<void> showProductPriceSheet(
  BuildContext context,
  ProductPrices product,
  PriceComparisonViewModel vm,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) => _ProductPriceSheet(
        product: product,
        insights: vm.insightsOf(product, AppFormatters.rupiah)),
  );
}

class _ProductPriceSheet extends StatelessWidget {
  const _ProductPriceSheet({required this.product, required this.insights});

  final ProductPrices product;
  final List<String> insights;

  String _where(PurchaseRecord p) {
    final String branch = (p.storeBranch ?? '').trim();
    return branch.isEmpty ? p.merchantName : '${p.merchantName} $branch';
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final ProductPrices p = product;
    final List<PurchaseRecord> history = p.purchases.reversed.toList();
    final double maxAverage = p.stores
        .map((StorePrice s) => s.average)
        .reduce((double a, double b) => a > b ? a : b);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController controller) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.cardLarge),
            ),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xl),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(p.name, style: textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                '${p.categoryName ?? 'Barang'} · ${p.count} pembelian · ${p.storeCount} toko',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),

              // Statistik harga satuan.
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      label: 'Terendah',
                      value: AppFormatters.rupiah(p.lowest),
                      color: AppColors.forest,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatTile(
                      label: 'Rata-rata',
                      value: AppFormatters.rupiah(p.average),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatTile(
                      label: 'Tertinggi',
                      value: AppFormatters.rupiah(p.highest),
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Kesimpulan dalam kalimat.
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.emeraldTint,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < insights.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(AppIcons.lightbulb,
                                size: 16, color: AppColors.emeraldDeep),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                insights[i],
                                style: textTheme.bodyMedium
                                    ?.copyWith(color: AppColors.emeraldDeep),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),
              Text('Perkembangan harga', style: textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              if (p.count < 2)
                Text(
                  'Grafik muncul setelah barang ini dibeli minimal dua kali.',
                  style: textTheme.bodySmall,
                )
              else
                PriceLineChart(
                  points: <PricePoint>[
                    for (final PurchaseRecord r in p.purchases)
                      PricePoint(date: r.date, price: r.unitPrice),
                  ],
                ),

              const SizedBox(height: AppSpacing.lg),
              Text('Perbandingan antar toko', style: textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Berdasarkan harga satuan rata-rata.',
                  style: textTheme.bodySmall),
              const SizedBox(height: AppSpacing.sm),
              for (int i = 0; i < p.stores.length; i++)
                _StoreRow(
                  store: p.stores[i],
                  fraction:
                      maxAverage <= 0 ? 0 : p.stores[i].average / maxAverage,
                  cheapest: p.isComparable && i == 0,
                ),

              const SizedBox(height: AppSpacing.lg),
              Text('Riwayat pembelian', style: textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              for (final PurchaseRecord r in history)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_where(r), style: textTheme.bodyMedium),
                            Text(
                              AppFormatters.longDate(r.date),
                              style: textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            AppFormatters.rupiah(r.unitPrice),
                            style: AppTextStyles.amount(
                              size: 14,
                              weight: FontWeight.w600,
                              color: r.itemId == p.cheapestPurchase.itemId &&
                                      p.count > 1
                                  ? AppColors.forest
                                  : AppColors.slateDark,
                            ),
                          ),
                          if (r.quantity != 1)
                            Text(
                              '${r.quantity == r.quantity.roundToDouble() ? r.quantity.round() : r.quantity} × = ${AppFormatters.rupiah(r.totalPrice)}',
                              style: textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.labelSmall),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTextStyles.amount(
                size: 15,
                color: color ?? AppColors.slateDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreRow extends StatelessWidget {
  const _StoreRow({
    required this.store,
    required this.fraction,
    required this.cheapest,
  });

  final StorePrice store;
  final double fraction;
  final bool cheapest;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Color bar = cheapest ? AppColors.emerald : AppColors.coolGray;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(store.merchant,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall),
                    ),
                    if (cheapest) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.emeraldTint,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Termurah',
                          style: textTheme.labelSmall?.copyWith(
                            color: AppColors.emeraldDeep,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                AppFormatters.rupiah(store.average),
                style: AppTextStyles.amount(size: 14, color: bar),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(bar),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${store.purchases}× dibeli · kisaran ${AppFormatters.rupiah(store.lowest)}'
            '${store.lowest == store.highest ? '' : ' – ${AppFormatters.rupiah(store.highest)}'}'
            ' · terakhir ${AppFormatters.shortDate(store.latestDate)}',
            style: textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
