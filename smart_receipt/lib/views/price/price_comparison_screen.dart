import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../services/price_comparison_service.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/price_comparison_viewmodel.dart';
import '../widgets/empty_state.dart';
import 'product_price_sheet.dart';

/// Bandingkan harga: seluruh barang yang pernah dibeli, harga di tiap toko,
/// dan apakah harganya naik atau turun. [initialQuery] membuka barang yang
/// cocok langsung (mis. dari hasil pencarian).
class PriceComparisonScreen extends StatelessWidget {
  const PriceComparisonScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PriceComparisonViewModel>(
      create: (BuildContext context) => PriceComparisonViewModel(
        authViewModel: context.read<AuthViewModel>(),
        transactionRepository: context.read<TransactionRepository>(),
      ),
      child: _PriceComparisonView(initialQuery: initialQuery),
    );
  }
}

class _PriceComparisonView extends StatefulWidget {
  const _PriceComparisonView({this.initialQuery});

  final String? initialQuery;

  @override
  State<_PriceComparisonView> createState() => _PriceComparisonViewState();
}

class _PriceComparisonViewState extends State<_PriceComparisonView> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Memuat setelah frame pertama: load() memberi tahu pendengar, dan itu
    // tidak boleh terjadi saat layar sedang dibangun.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_init());
    });
  }

  Future<void> _init() async {
    final PriceComparisonViewModel vm =
        context.read<PriceComparisonViewModel>();
    await vm.load();
    final String query = (widget.initialQuery ?? '').trim();
    if (!mounted || query.isEmpty) return;

    _controller.text = query;
    vm.setQuery(query);
    final ProductPrices? match = vm.bestMatch(query);
    if (match != null) await showProductPriceSheet(context, match, vm);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _sortLabel(ProductSort sort) => switch (sort) {
        ProductSort.mostBought => 'Paling sering dibeli',
        ProductSort.biggestSaving => 'Selisih antar toko terbesar',
        ProductSort.priceUp => 'Harga naik terbanyak',
        ProductSort.priceDown => 'Harga turun terbanyak',
        ProductSort.name => 'Nama (A–Z)',
      };

  @override
  Widget build(BuildContext context) {
    final PriceComparisonViewModel vm =
        context.watch<PriceComparisonViewModel>();
    final TextTheme textTheme = Theme.of(context).textTheme;
    final List<ProductPrices> products = vm.products;

    Widget body;
    if (vm.isLoading && vm.allProducts.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (vm.errorMessage != null) {
      body = Center(
        child: EmptyState(
          icon: AppIcons.wifiOff,
          title: 'Tidak dapat memuat',
          message: vm.errorMessage!,
          actionLabel: 'Coba Lagi',
          onAction: vm.load,
        ),
      );
    } else if (vm.allProducts.isEmpty) {
      body = Center(
        child: EmptyState(
          icon: AppIcons.trendingUp,
          title: 'Belum ada data harga',
          message:
              'Pindai atau catat beberapa struk. Harga tiap barang akan dibandingkan di sini.',
        ),
      );
    } else {
      body = RefreshIndicator(
        color: AppColors.emerald,
        onRefresh: vm.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.emeraldTint,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.lightbulb,
                      size: 20, color: AppColors.emeraldDeep),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${vm.allProducts.length} barang tercatat. '
                      '${vm.comparableCount} di antaranya pernah dibeli di lebih dari satu toko, sehingga harganya bisa dibandingkan.',
                      style: textTheme.bodySmall
                          ?.copyWith(color: AppColors.emeraldDeep),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _controller,
              onChanged: vm.setQuery,
              decoration: InputDecoration(
                hintText: 'Cari barang, mis. telur, aqua...',
                prefixIcon:
                    Icon(AppIcons.search, size: 20, color: AppColors.coolGray),
                suffixIcon: vm.query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus pencarian',
                        icon: Icon(AppIcons.close, size: 18),
                        onPressed: () {
                          _controller.clear();
                          vm.setQuery('');
                        },
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                FilterChip(
                  label: const Text('Bisa dibandingkan'),
                  selected: vm.onlyComparable,
                  onSelected: vm.setOnlyComparable,
                  selectedColor: AppColors.emeraldTint,
                  checkmarkColor: AppColors.emeraldDeep,
                  backgroundColor: AppColors.white,
                  side: BorderSide(
                    color: vm.onlyComparable
                        ? AppColors.emerald
                        : AppColors.border,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<ProductSort>(
                      tooltip: 'Urutkan',
                      initialValue: vm.sort,
                      onSelected: vm.setSort,
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<ProductSort>>[
                        for (final ProductSort s in ProductSort.values)
                          PopupMenuItem<ProductSort>(
                            value: s,
                            child: Text(_sortLabel(s)),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(AppIcons.arrowUpDown, size: 18),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _sortLabel(vm.sort),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelLarge,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (products.isEmpty)
              EmptyState(
                icon: AppIcons.search,
                title: 'Barang tidak ditemukan',
                message: vm.onlyComparable
                    ? 'Tidak ada barang yang cocok yang pernah dibeli di lebih dari satu toko.'
                    : 'Tidak ada barang yang cocok dengan pencarian.',
                actionLabel: 'Hapus pencarian',
                onAction: () {
                  _controller.clear();
                  vm
                    ..setQuery('')
                    ..setOnlyComparable(false);
                },
              )
            else
              for (final ProductPrices p in products)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ProductTile(
                    product: p,
                    onTap: () => showProductPriceSheet(context, p, vm),
                  ),
                ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Bandingkan Harga')),
      body: SafeArea(child: body),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});

  final ProductPrices product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final PriceChange? change = product.latestChange;
    final StorePrice? cheap = product.cheapestStore;
    final double? saving = product.potentialSaving;

    return Container(
      decoration: AppDecorations.card(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.mint,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(AppIcons.shoppingBasket,
                          size: 20, color: AppColors.emerald),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall),
                          const SizedBox(height: 2),
                          Text(
                            '${product.count}× dibeli · ${product.storeCount} toko',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          AppFormatters.rupiah(product.latest.unitPrice),
                          style: AppTextStyles.amount(size: 15),
                        ),
                        if (change != null && change.trend != PriceTrend.flat)
                          _TrendBadge(change: change)
                        else
                          Text('terakhir', style: textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
                if (cheap != null && saving != null && saving >= 0.03) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.emeraldTint,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Text(
                      'Termurah di ${cheap.merchant} · hemat ${(saving * 100).round()}% dari toko termahal',
                      style: textTheme.labelMedium
                          ?.copyWith(color: AppColors.emeraldDeep),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lencana perubahan harga: naik = merah (merugikan), turun = hijau.
class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.change});

  final PriceChange change;

  @override
  Widget build(BuildContext context) {
    final bool up = change.trend == PriceTrend.up;
    final Color color = up ? AppColors.error : AppColors.emeraldDeep;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: up ? AppColors.errorTint : AppColors.emeraldTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? AppIcons.trendingUp : AppIcons.trendingDown,
              size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            '${(change.percent.abs() * 100).round()}%',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
