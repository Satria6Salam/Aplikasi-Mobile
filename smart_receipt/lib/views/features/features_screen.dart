import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../widgets/fade_slide_in.dart';
import '../widgets/pressable_scale.dart';

/// Satu fitur pada menu Fitur.
class FeatureSpec {
  const FeatureSpec({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String route;
}

/// Sekelompok fitur dengan judul dan penjelasan singkat.
class FeatureSection {
  const FeatureSection({
    required this.title,
    required this.subtitle,
    required this.features,
  });

  final String title;
  final String subtitle;
  final List<FeatureSpec> features;
}

/// Pengelompokan fitur berdasarkan tujuan pengguna, bukan urutan pembuatannya.
List<FeatureSection> featureSections() => <FeatureSection>[
      FeatureSection(
        title: 'Catat & Rencanakan',
        subtitle: 'Uang masuk, uang keluar, dan tujuan menabung',
        features: <FeatureSpec>[
          FeatureSpec(
            icon: AppIcons.wallet,
            color: const Color(0xFF16A34A),
            title: 'Pemasukan',
            subtitle: 'Uang saku, gaji, dan sisa uang bebas',
            route: AppRoutes.incomes,
          ),
          FeatureSpec(
            icon: AppIcons.penLine,
            color: const Color(0xFF3B82F6),
            title: 'Catat Manual',
            subtitle: 'Parkir, jajan, dan langganan bulanan',
            route: AppRoutes.manualEntry,
          ),
          FeatureSpec(
            icon: AppIcons.piggyBank,
            color: const Color(0xFF16855A),
            title: 'Anggaran',
            subtitle: 'Batas belanja bulanan per kategori',
            route: AppRoutes.budget,
          ),
          FeatureSpec(
            icon: AppIcons.piggyBank,
            color: const Color(0xFFEC4899),
            title: 'Target Tabungan',
            subtitle: 'Menabung untuk barang impian',
            route: AppRoutes.savings,
          ),
          FeatureSpec(
            icon: AppIcons.shoppingCart,
            color: const Color(0xFF0EA5E9),
            title: 'Rencana Belanja',
            subtitle: 'Daftar belanja yang tercoret otomatis',
            route: AppRoutes.shoppingPlan,
          ),
        ],
      ),
      FeatureSection(
        title: 'Analisis & Pencarian',
        subtitle: 'Pahami pola belanja dan temukan catatan lama',
        features: <FeatureSpec>[
          FeatureSpec(
            icon: AppIcons.pieChart,
            color: const Color(0xFF14B8A6),
            title: 'Analisis',
            subtitle: 'Rekap, tren, dan wawasan pengeluaran',
            route: AppRoutes.analysis,
          ),
          FeatureSpec(
            icon: AppIcons.slidersHorizontal,
            color: const Color(0xFF8B5CF6),
            title: 'Pencarian Lanjutan',
            subtitle: 'Cari toko, barang, tanggal, dan total',
            route: AppRoutes.search,
          ),
          FeatureSpec(
            icon: AppIcons.trendingUp,
            color: const Color(0xFFF59E0B),
            title: 'Bandingkan Harga',
            subtitle: 'Harga barang antar toko',
            route: AppRoutes.priceCompare,
          ),
          FeatureSpec(
            icon: AppIcons.map,
            color: const Color(0xFFE11D48),
            title: 'Peta Toko',
            subtitle: 'Toko tempat Anda berbelanja',
            route: AppRoutes.storeMap,
          ),
        ],
      ),
      FeatureSection(
        title: 'Kelola',
        subtitle: 'Sesuaikan aplikasi dengan kebutuhan Anda',
        features: <FeatureSpec>[
          FeatureSpec(
            icon: AppIcons.tags,
            color: const Color(0xFFF97316),
            title: 'Kategori',
            subtitle: 'Nama, ikon, warna, dan sembunyikan',
            route: AppRoutes.categories,
          ),
        ],
      ),
    ];

/// Menu Fitur: semua alat selain Beranda, Riwayat, Scan, dan Profil, dikelompokkan
/// menurut tujuannya agar mudah ditemukan.
class FeaturesScreen extends StatelessWidget {
  const FeaturesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final List<FeatureSection> sections = featureSections();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            FadeSlideIn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fitur', style: textTheme.headlineMedium),
                  const SizedBox(height: 2),
                  Text(
                    'Semua alat untuk mengelola keuangan Anda',
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            for (int s = 0; s < sections.length; s++) ...[
              const SizedBox(height: AppSpacing.lg),
              FadeSlideIn(
                delay: Duration(milliseconds: 60 * (s + 1)),
                child: _SectionView(section: sections[s]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionView extends StatelessWidget {
  const _SectionView({required this.section});

  final FeatureSection section;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(section.title, style: textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(section.subtitle, style: textTheme.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        // Dua kolom; kartu ganjil terakhir tetap selebar satu kolom.
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            const double gap = 12;
            final double width = (box.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final FeatureSpec f in section.features)
                  SizedBox(width: width, child: _FeatureCard(spec: f)),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.spec});

  final FeatureSpec spec;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return PressableScale(
      child: Container(
        decoration: AppDecorations.card(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.card),
            onTap: () => context.push(spec.route),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 112),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: spec.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: Icon(spec.icon, size: 20, color: spec.color),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      spec.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      spec.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.coolGray,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
