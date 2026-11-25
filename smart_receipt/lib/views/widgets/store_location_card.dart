import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../viewmodels/scan_viewmodel.dart';
import '../location/location_picker_screen.dart';
import 'custom_textfield.dart';
import 'message_banner.dart';
import 'store_map.dart';

/// Kartu "Lokasi Toko" pada pratinjau: cabang dan alamat hasil bacaan struk
/// (dapat disunting), status pencarian di peta, pratinjau pin, serta tombol
/// cari ulang / pakai lokasi saya / atur di peta.
class StoreLocationCard extends StatefulWidget {
  const StoreLocationCard({super.key});

  @override
  State<StoreLocationCard> createState() => _StoreLocationCardState();
}

class _StoreLocationCardState extends State<StoreLocationCard> {
  late final TextEditingController _addressController;
  late final TextEditingController _branchController;

  @override
  void initState() {
    super.initState();
    final ScanDraft? draft = context.read<ScanViewModel>().draft;
    _addressController = TextEditingController(text: draft?.storeAddress ?? '');
    _branchController = TextEditingController(text: draft?.storeBranch ?? '');
  }

  @override
  void dispose() {
    _addressController.dispose();
    _branchController.dispose();
    super.dispose();
  }

  Future<void> _search(ScanViewModel scan) async {
    FocusScope.of(context).unfocus();
    await scan.searchLocation();
  }

  Future<void> _pickOnMap(ScanViewModel scan) async {
    FocusScope.of(context).unfocus();
    final StoreLocation? current = scan.draft?.location;
    final LatLng? picked = await showLocationPicker(
      context,
      initial: current?.point,
      initialZoom: current == null ? 17 : zoomForConfidence(current.confidence),
    );
    if (picked != null) await scan.setManualLocation(picked);
  }

  @override
  Widget build(BuildContext context) {
    final ScanViewModel scan = context.watch<ScanViewModel>();
    final ScanDraft? draft = scan.draft;
    if (draft == null || !scan.locationEnabled) return const SizedBox.shrink();

    // Alamat bisa terisi otomatis dari peta setelah titik dipilih manual.
    if (_addressController.text.isEmpty && draft.storeAddress.isNotEmpty) {
      _addressController.text = draft.storeAddress;
    }

    final TextTheme textTheme = Theme.of(context).textTheme;
    final StoreLocation? location = draft.location;
    final bool searching =
        draft.locationStatus == LocationLookupStatus.searching;
    final StoreAddress extracted = draft.extractedAddress;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: AppDecorations.card(radius: AppRadius.cardLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.mint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(AppIcons.mapPin, size: 18, color: AppColors.emerald),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Lokasi Toko', style: textTheme.titleMedium),
              ),
              _StatusChip(draft: draft),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          CustomTextField(
            label: 'Cabang (opsional)',
            hint: 'Contoh: Urek Urek',
            controller: _branchController,
            prefixIcon: AppIcons.store,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: scan.updateStoreBranch,
          ),
          const SizedBox(height: AppSpacing.md),
          CustomTextField(
            label: 'Alamat Toko',
            hint: 'Jalan, kecamatan, kota/kabupaten, kode pos',
            controller: _addressController,
            prefixIcon: AppIcons.mapPinned,
            maxLines: 3,
            textCapitalization: TextCapitalization.words,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            onChanged: scan.updateStoreAddress,
          ),
          if (extracted.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('Terbaca dari struk:', style: textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (extracted.street != null)
                  _PartChip('Jalan', extracted.street!),
                if (extracted.village != null)
                  _PartChip('Kel./Desa', extracted.village!),
                if (extracted.district != null)
                  _PartChip('Kecamatan', extracted.district!),
                if (extracted.city != null) _PartChip('Kota', extracted.city!),
                if (extracted.postalCode != null)
                  _PartChip('Kode pos', extracted.postalCode!),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (searching) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(minHeight: 4),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              draft.locationMessage ??
                  'Mencari "${scan.locationSearchName}" di peta...',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (location != null) ...[
            StoreMapPreview(
              point: location.point,
              zoom: zoomForConfidence(location.confidence),
              overlayLabel: 'Ketuk untuk ubah',
              onTap: searching ? null : () => _pickOnMap(scan),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (location.displayName.isNotEmpty)
              Text(
                'Menurut peta: ${ScanViewModel.shortAddress(location.displayName)}',
                style: textTheme.bodySmall,
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (!searching && draft.locationMessage != null) ...[
            MessageBanner(
              message: draft.locationMessage!,
              type: draft.locationStatus == LocationLookupStatus.failed
                  ? BannerType.error
                  : BannerType.warning,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ActionChip(
                icon: AppIcons.search,
                label: 'Cari Ulang',
                onTap: searching ? null : () => _search(scan),
              ),
              _ActionChip(
                icon: AppIcons.locate,
                label: 'Lokasi Saya',
                onTap: searching ? null : scan.useCurrentLocation,
              ),
              _ActionChip(
                icon: AppIcons.map,
                label: 'Atur di Peta',
                onTap: searching ? null : () => _pickOnMap(scan),
              ),
              if (location != null)
                _ActionChip(
                  icon: AppIcons.mapPinOff,
                  label: 'Hapus',
                  onTap: searching ? null : scan.clearLocation,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.draft});

  final ScanDraft draft;

  @override
  Widget build(BuildContext context) {
    final StoreLocation? location = draft.location;
    late final String text;
    late final Color fg;
    late final Color bg;
    if (draft.locationStatus == LocationLookupStatus.searching) {
      text = 'Mencari...';
      fg = AppColors.slateDark;
      bg = AppColors.border;
    } else if (location == null) {
      text = 'Belum ada titik';
      fg = AppColors.warningDeep;
      bg = AppColors.warningTint;
    } else if (location.isAccurate) {
      text = 'Akurat · ${LocationSource.label(location.source)}';
      fg = AppColors.emeraldDeep;
      bg = AppColors.emeraldTint;
    } else {
      text = 'Perkiraan · ${location.precision.label}';
      fg = AppColors.warningDeep;
      bg = AppColors.warningTint;
    }
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: fg, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _PartChip extends StatelessWidget {
  const _PartChip(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.offWhite,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: AppColors.coolGray),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: AppColors.slateDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: AppColors.emerald),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
    );
  }
}
