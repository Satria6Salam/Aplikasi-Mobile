import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/store_map_viewmodel.dart';
import '../widgets/empty_state.dart';
import '../widgets/store_map.dart';

/// Peta seluruh toko tempat pengguna berbelanja (dari transaksi berlokasi).
class StoreMapScreen extends StatelessWidget {
  const StoreMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<StoreMapViewModel>(
      create: (BuildContext context) => StoreMapViewModel(
        authViewModel: context.read<AuthViewModel>(),
        transactionRepository: context.read<TransactionRepository>(),
      )..load(),
      child: const _StoreMapView(),
    );
  }
}

class _StoreMapView extends StatefulWidget {
  const _StoreMapView();

  @override
  State<_StoreMapView> createState() => _StoreMapViewState();
}

class _StoreMapViewState extends State<_StoreMapView> {
  final MapController _controller = MapController();

  void _focus(StoreMapViewModel vm, StorePlace place) {
    vm.select(place);
    _controller.move(place.point, 17);
  }

  @override
  Widget build(BuildContext context) {
    final StoreMapViewModel vm = context.watch<StoreMapViewModel>();
    final TextTheme textTheme = Theme.of(context).textTheme;

    Widget body;
    if (vm.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (vm.errorMessage != null) {
      body = Center(
        child: EmptyState(
          icon: AppIcons.mapPinOff,
          title: 'Peta tidak dapat dimuat',
          message: vm.errorMessage!,
          actionLabel: 'Coba Lagi',
          onAction: vm.load,
        ),
      );
    } else if (vm.places.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: EmptyState(
            icon: AppIcons.map,
            title: 'Belum ada toko di peta',
            message:
                'Lokasi toko tersimpan otomatis saat Anda memindai struk yang mencantumkan alamat, atau saat Anda mengatur titiknya di pratinjau.',
          ),
        ),
      );
    } else {
      final List<LatLng> points =
          vm.places.map((StorePlace p) => p.point).toList();
      final StorePlace? selected = vm.selected;
      body = Column(
        children: [
          Expanded(
            flex: 3,
            child: FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: points.first,
                initialZoom: 15,
                initialCameraFit: points.length > 1
                    ? CameraFit.coordinates(
                        coordinates: points,
                        padding: const EdgeInsets.all(56),
                        maxZoom: 16,
                      )
                    : null,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: (TapPosition _, LatLng __) => vm.select(null),
              ),
              children: [
                osmTileLayer(),
                MarkerLayer(
                  markers: <Marker>[
                    for (final StorePlace p in vm.places)
                      Marker(
                        point: p.point,
                        width: 48,
                        height: 48,
                        alignment: Alignment.topCenter,
                        child: GestureDetector(
                          onTap: () => _focus(vm, p),
                          child: StorePin(
                            size: identical(p, selected) ? 48 : 40,
                            color: identical(p, selected)
                                ? AppColors.forest
                                : AppColors.emerald,
                          ),
                        ),
                      ),
                  ],
                ),
                osmAttribution(),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: vm.places.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (BuildContext context, int i) {
                final StorePlace p = vm.places[i];
                final bool active = identical(p, selected);
                return InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  onTap: () => _focus(vm, p),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: AppDecorations.card().copyWith(
                      border: Border.all(
                        color: active ? AppColors.emerald : AppColors.border,
                        width: active ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(AppIcons.store, color: AppColors.emerald),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.title, style: textTheme.titleSmall),
                              if (p.address != null && p.address!.isNotEmpty)
                                Text(
                                  p.address!,
                                  maxLines: active ? 4 : 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall,
                                ),
                              const SizedBox(height: 4),
                              Text(
                                '${p.visits}× belanja · terakhir ${AppFormatters.longDate(p.lastVisit)}',
                                style: textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppFormatters.rupiah(p.totalSpent),
                          style: AppTextStyles.amount(size: 14),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peta Toko'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: Icon(AppIcons.refresh),
            onPressed: vm.isLoading ? null : vm.load,
          ),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}
