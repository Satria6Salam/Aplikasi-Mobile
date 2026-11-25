import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/purchase_record_model.dart';
import '../../data/models/transaction_filter.dart';
import '../../data/models/transaction_model.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/search_viewmodel.dart';
import '../widgets/empty_state.dart';
import '../widgets/message_banner.dart';
import '../widgets/transaction_card.dart';
import '../widgets/transaction_detail_sheet.dart';
import 'search_filter_sheets.dart';

/// Pencarian lanjutan: mencari transaksi dan barang di SEMUA periode dengan
/// filter tanggal, total struk, dan kategori.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SearchViewModel>(
      create: (BuildContext context) => SearchViewModel(
        authViewModel: context.read<AuthViewModel>(),
        transactionRepository: context.read<TransactionRepository>(),
        categoryRepository: context.read<CategoryRepository>(),
      )..load(),
      child: const _SearchView(),
    );
  }
}

class _SearchView extends StatefulWidget {
  const _SearchView();

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _sortLabel(SearchSort sort) => switch (sort) {
        SearchSort.newest => 'Terbaru',
        SearchSort.oldest => 'Terlama',
        SearchSort.highest => 'Total terbesar',
        SearchSort.lowest => 'Total terkecil',
      };

  String _dateLabel(TransactionFilter f) {
    final DateTime? from = f.from;
    final DateTime? to = f.to;
    if (from != null && to != null) {
      return '${AppFormatters.shortDate(from)} – ${AppFormatters.shortDate(to)}';
    }
    if (from != null) return 'Sejak ${AppFormatters.shortDate(from)}';
    if (to != null) return 'Sampai ${AppFormatters.shortDate(to)}';
    return 'Tanggal';
  }

  String _totalLabel(TransactionFilter f) {
    final double? min = f.minTotal;
    final double? max = f.maxTotal;
    if (min != null && max != null) {
      return '${AppFormatters.rupiah(min)} – ${AppFormatters.rupiah(max)}';
    }
    if (min != null) return '≥ ${AppFormatters.rupiah(min)}';
    if (max != null) return '≤ ${AppFormatters.rupiah(max)}';
    return 'Total struk';
  }

  String _categoryLabel(SearchViewModel vm) {
    final Set<int> ids = vm.filter.categoryIds;
    if (ids.isEmpty) return 'Kategori';
    if (ids.length == 1) return vm.categoryName(ids.first);
    return '${ids.length} kategori';
  }

  Future<void> _pickDate(SearchViewModel vm) async {
    final DateChoice? choice = await showDateFilterSheet(
      context,
      from: vm.filter.from,
      to: vm.filter.to,
    );
    if (choice != null) vm.setDateRange(choice.from, choice.to);
  }

  Future<void> _pickTotal(SearchViewModel vm) async {
    final TotalChoice? choice = await showTotalFilterSheet(
      context,
      min: vm.filter.minTotal,
      max: vm.filter.maxTotal,
    );
    if (choice != null) vm.setTotalRange(choice.min, choice.max);
  }

  Future<void> _pickCategories(SearchViewModel vm) async {
    final Set<int>? ids = await showCategoryFilterSheet(
      context,
      categories: vm.categories,
      selected: vm.filter.categoryIds,
    );
    if (ids != null) vm.setCategories(ids);
  }

  Future<void> _openTransaction(
      SearchViewModel vm, TransactionModel transaction) async {
    await showTransactionDetailSheet(context, transaction);
    // Transaksi mungkin dihapus dari lembar rincian.
    if (mounted) await vm.search();
  }

  void _compare(SearchViewModel vm) {
    context.push(AppRoutes.priceCompare, extra: vm.filter.query.trim());
  }

  @override
  Widget build(BuildContext context) {
    final SearchViewModel vm = context.watch<SearchViewModel>();
    final TransactionFilter f = vm.filter;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Pencarian Lanjutan')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onChanged: vm.setQuery,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Cari toko, barang, alamat, atau catatan...',
                        prefixIcon: Icon(AppIcons.search,
                            size: 20, color: AppColors.coolGray),
                        suffixIcon: f.query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Hapus kata kunci',
                                icon: Icon(AppIcons.close, size: 18),
                                onPressed: () {
                                  _controller.clear();
                                  vm.setQuery('');
                                },
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: AppDecorations.card(radius: AppRadius.control),
                    child: PopupMenuButton<SearchSort>(
                      tooltip: 'Urutkan: ${_sortLabel(f.sort)}',
                      icon: Icon(AppIcons.arrowUpDown, size: 22),
                      initialValue: f.sort,
                      onSelected: vm.setSort,
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<SearchSort>>[
                        for (final SearchSort s in SearchSort.values)
                          PopupMenuItem<SearchSort>(
                            value: s,
                            child: Row(
                              children: [
                                Expanded(child: Text(_sortLabel(s))),
                                if (s == f.sort)
                                  Icon(AppIcons.check,
                                      size: 18, color: AppColors.emeraldDark),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                children: [
                  _FilterButton(
                    icon: AppIcons.calendar,
                    label: _dateLabel(f),
                    active: f.hasDateRange,
                    onTap: () => _pickDate(vm),
                    onClear: () => vm.setDateRange(null, null),
                  ),
                  _FilterButton(
                    icon: AppIcons.banknote,
                    label: _totalLabel(f),
                    active: f.hasTotalRange,
                    onTap: () => _pickTotal(vm),
                    onClear: () => vm.setTotalRange(null, null),
                  ),
                  _FilterButton(
                    icon: AppIcons.tags,
                    label: _categoryLabel(vm),
                    active: f.hasCategories,
                    onTap: () => _pickCategories(vm),
                    onClear: () => vm.setCategories(<int>{}),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.emerald,
                onRefresh: vm.search,
                child: _buildResults(context, vm, textTheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(
      BuildContext context, SearchViewModel vm, TextTheme textTheme) {
    final List<Widget> children = <Widget>[];

    if (vm.errorMessage != null) {
      children.add(MessageBanner(message: vm.errorMessage!));
    }

    children.add(
      Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.emeraldTint,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            Icon(AppIcons.receipt, size: 18, color: AppColors.emeraldDeep),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                vm.isLoading && vm.results.isEmpty
                    ? 'Mencari...'
                    : '${vm.results.length}${vm.isTruncated ? '+' : ''} transaksi',
                style: textTheme.labelLarge
                    ?.copyWith(color: AppColors.emeraldDeep),
              ),
            ),
            if (vm.isLoading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                AppFormatters.rupiah(vm.totalAmount),
                style: AppTextStyles.amount(
                    size: 15, color: AppColors.emeraldDeep),
              ),
          ],
        ),
      ),
    );

    if (vm.isTruncated) {
      children
        ..add(const SizedBox(height: AppSpacing.sm))
        ..add(const MessageBanner(
          message:
              'Hasil dibatasi 300 transaksi terbaru. Persempit dengan kata kunci atau filter.',
          type: BannerType.warning,
        ));
    }

    if (vm.purchases.isNotEmpty) {
      children
        ..add(const SizedBox(height: AppSpacing.md))
        ..add(_ItemMatchesCard(vm: vm, onCompare: () => _compare(vm)));
    }
    children.add(const SizedBox(height: AppSpacing.md));

    if (!vm.isLoading && vm.results.isEmpty) {
      children.add(
        EmptyState(
          icon: AppIcons.search,
          title: 'Tidak ada hasil',
          message: vm.filter.isEmpty
              ? 'Belum ada transaksi tersimpan.'
              : 'Tidak ada transaksi yang cocok. Coba kata kunci lain atau longgarkan filter.',
          actionLabel: vm.filter.isEmpty ? null : 'Hapus semua',
          onAction: () {
            _controller.clear();
            vm.clearAll();
          },
        ),
      );
    } else {
      for (final TransactionModel t in vm.results) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TransactionCard(
              key: ValueKey<int?>(t.id),
              transaction: t,
              onTap: () => _openTransaction(vm, t),
            ),
          ),
        );
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      children: children,
    );
  }
}

/// Tombol filter berbentuk chip; bila aktif tampil hijau dengan tombol hapus.
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.icon,
    required this.label,
    required this.active,
    this.onTap,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final Color fg = active ? AppColors.emeraldDeep : AppColors.slateDark;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active ? AppColors.emeraldTint : AppColors.white,
        shape: StadiumBorder(
          side:
              BorderSide(color: active ? AppColors.emerald : AppColors.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: fg),
                ),
                const SizedBox(width: 4),
                if (active && onClear != null)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onClear,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(AppIcons.close, size: 14, color: fg),
                    ),
                  )
                else
                  const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barang yang cocok dengan kata kunci: kapan terakhir dibeli, di mana, dan
/// berapa harganya, plus jalan pintas ke perbandingan harga.
class _ItemMatchesCard extends StatelessWidget {
  const _ItemMatchesCard({required this.vm, required this.onCompare});

  final SearchViewModel vm;
  final VoidCallback onCompare;

  String _where(PurchaseRecord p) {
    final String branch = (p.storeBranch ?? '').trim();
    return branch.isEmpty ? p.merchantName : '${p.merchantName} $branch';
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final ItemSearchSummary summary = vm.itemSummary!;
    final PurchaseRecord latest = summary.latest;
    final PurchaseRecord cheapest = summary.cheapest;
    final bool showCheapest = summary.count > 1 &&
        cheapest.itemId != latest.itemId &&
        cheapest.unitPrice < latest.unitPrice;
    final List<PurchaseRecord> recent = vm.purchases.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: AppDecorations.card(radius: AppRadius.cardLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(AppIcons.shoppingBasket, size: 18, color: AppColors.emerald),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Barang cocok · ${summary.count} pembelian di ${summary.storeCount} toko',
                  style: textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _Highlight(
            label: 'Terakhir beli',
            record: latest,
            where: _where(latest),
            color: AppColors.emeraldDeep,
          ),
          if (showCheapest) ...[
            const SizedBox(height: 8),
            _Highlight(
              label: 'Termurah',
              record: cheapest,
              where: _where(cheapest),
              color: AppColors.forest,
            ),
          ],
          const Divider(height: AppSpacing.lg),
          for (final PurchaseRecord p in recent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.itemName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodyMedium),
                        Text(
                          '${_where(p)} · ${AppFormatters.shortDate(p.date)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppFormatters.rupiah(p.unitPrice),
                    style:
                        AppTextStyles.amount(size: 13, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          if (vm.purchases.length > recent.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${vm.purchases.length - recent.length} pembelian lainnya',
                style: textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCompare,
              icon: Icon(AppIcons.trendingUp, size: 18),
              label: const Text('Bandingkan harga antar toko'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Highlight extends StatelessWidget {
  const _Highlight({
    required this.label,
    required this.record,
    required this.where,
    required this.color,
  });

  final String label;
  final PurchaseRecord record;
  final String where;
  final Color color;

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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: textTheme.labelSmall?.copyWith(color: color)),
                const SizedBox(height: 2),
                Text(record.itemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall),
                Text(
                  '$where · ${AppFormatters.longDate(record.date)}',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                AppFormatters.rupiah(record.unitPrice),
                style: AppTextStyles.amount(size: 16, color: color),
              ),
              if (record.quantity != 1)
                Text(
                  '× ${record.quantity == record.quantity.roundToDouble() ? record.quantity.round() : record.quantity}',
                  style: textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
