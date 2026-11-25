import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../viewmodels/dashboard_viewmodel.dart';
import '../../viewmodels/qris_pending_viewmodel.dart';

/// Pengingat di Dasbor: ada QRIS yang masih menunggu struk. Tidak tampil bila
/// tidak ada.
class QrisPendingBanner extends StatefulWidget {
  const QrisPendingBanner({super.key});

  @override
  State<QrisPendingBanner> createState() => _QrisPendingBannerState();
}

class _QrisPendingBannerState extends State<QrisPendingBanner> {
  String? _loadedKey;

  @override
  Widget build(BuildContext context) {
    final DashboardViewModel dash = context.watch<DashboardViewModel>();
    final QrisPendingViewModel vm = context.watch<QrisPendingViewModel>();
    final String key = '${dash.total}-${dash.transactionCount}';

    // Muat ulang saat Dasbor berubah (mis. setelah struk melengkapi QRIS).
    if (!dash.isLoading && key != _loadedKey) {
      _loadedKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(vm.load());
      });
    }

    final int count = vm.items.length;
    if (count == 0) return const SizedBox.shrink();
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: AppColors.warningTint,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            Icon(AppIcons.hourglass, size: 20, color: AppColors.warningDeep),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$count QRIS menunggu struk',
                style: textTheme.labelLarge
                    ?.copyWith(color: AppColors.warningDeep),
              ),
            ),
            TextButton(
              onPressed: () async {
                await context.push(AppRoutes.qrisPending);
                if (context.mounted) unawaited(vm.load());
              },
              child: const Text('Lihat'),
            ),
          ],
        ),
      ),
    );
  }
}
