import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/thousands_separator_formatter.dart';
import '../../data/models/category_model.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_textfield.dart';

/// Rentang tanggal pilihan pengguna; keduanya null berarti "semua tanggal".
typedef DateChoice = ({DateTime? from, DateTime? to});

/// Rentang total struk pilihan pengguna; keduanya null berarti "semua".
typedef TotalChoice = ({double? min, double? max});

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Kerangka lembar bawah yang seragam dengan lembar lain di aplikasi.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.cardLarge),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.md),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<T?> _showSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: builder,
  );
}

// ================================================================ tanggal

/// Memilih rentang tanggal (pilihan cepat atau kalender). Mengembalikan null
/// bila dibatalkan.
Future<DateChoice?> showDateFilterSheet(
  BuildContext context, {
  DateTime? from,
  DateTime? to,
}) {
  return _showSheet<DateChoice>(
    context,
    (BuildContext sheetContext) => _DateFilterSheet(from: from, to: to),
  );
}

class _DateFilterSheet extends StatelessWidget {
  const _DateFilterSheet({this.from, this.to});

  final DateTime? from;
  final DateTime? to;

  Future<void> _custom(BuildContext context) async {
    final DateTime today = _dateOnly(DateTime.now());
    final DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today.add(const Duration(days: 1)),
      initialDateRange: from != null && to != null
          ? DateTimeRange(start: from!, end: to!)
          : null,
      helpText: 'Pilih rentang tanggal',
      saveText: 'Terapkan',
    );
    if (range != null && context.mounted) {
      Navigator.of(context).pop<DateChoice>(
        (from: _dateOnly(range.start), to: _dateOnly(range.end)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime today = _dateOnly(DateTime.now());
    final List<(String, DateChoice)> presets = <(String, DateChoice)>[
      ('Semua tanggal', (from: null, to: null)),
      (
        '7 hari terakhir',
        (from: today.subtract(const Duration(days: 6)), to: today)
      ),
      (
        '30 hari terakhir',
        (from: today.subtract(const Duration(days: 29)), to: today)
      ),
      ('Bulan ini', (from: DateTime(today.year, today.month), to: today)),
      (
        'Bulan lalu',
        (
          from: DateTime(today.year, today.month - 1),
          to: DateTime(today.year, today.month, 0),
        )
      ),
      ('Tahun ini', (from: DateTime(today.year), to: today)),
    ];

    return _SheetFrame(
      title: 'Filter tanggal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (String label, DateChoice choice) in presets)
                ActionChip(
                  label: Text(label),
                  backgroundColor: AppColors.white,
                  side: const BorderSide(color: AppColors.border),
                  onPressed: () =>
                      Navigator.of(context).pop<DateChoice>(choice),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          CustomButton(
            label: 'Pilih tanggal sendiri',
            icon: AppIcons.calendarDays,
            variant: CustomButtonVariant.secondary,
            onPressed: () => _custom(context),
          ),
        ],
      ),
    );
  }
}

// ============================================================ total struk

/// Memilih batas total struk. Mengembalikan null bila dibatalkan.
Future<TotalChoice?> showTotalFilterSheet(
  BuildContext context, {
  double? min,
  double? max,
}) {
  return _showSheet<TotalChoice>(
    context,
    (BuildContext sheetContext) => _TotalFilterSheet(min: min, max: max),
  );
}

class _TotalFilterSheet extends StatefulWidget {
  const _TotalFilterSheet({this.min, this.max});

  final double? min;
  final double? max;

  @override
  State<_TotalFilterSheet> createState() => _TotalFilterSheetState();
}

class _TotalFilterSheetState extends State<_TotalFilterSheet> {
  late final TextEditingController _min = TextEditingController(
    text: widget.min == null ? '' : AppFormatters.amountInput(widget.min!),
  );
  late final TextEditingController _max = TextEditingController(
    text: widget.max == null ? '' : AppFormatters.amountInput(widget.max!),
  );
  String? _error;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  double? _parse(String text) {
    final String digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return double.tryParse(digits);
  }

  void _setPreset(double? min, double? max) {
    setState(() {
      _error = null;
      _min.text = min == null ? '' : AppFormatters.amountInput(min);
      _max.text = max == null ? '' : AppFormatters.amountInput(max);
    });
  }

  void _apply() {
    final double? min = _parse(_min.text);
    final double? max = _parse(_max.text);
    if (min != null && max != null && min > max) {
      setState(() => _error = 'Batas bawah tidak boleh melebihi batas atas.');
      return;
    }
    Navigator.of(context).pop<TotalChoice>((min: min, max: max));
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: 'Filter total struk',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('Di bawah Rp 50.000'),
                onPressed: () => _setPreset(null, 50000),
                backgroundColor: AppColors.white,
                side: const BorderSide(color: AppColors.border),
              ),
              ActionChip(
                label: const Text('Rp 50.000 – 200.000'),
                onPressed: () => _setPreset(50000, 200000),
                backgroundColor: AppColors.white,
                side: const BorderSide(color: AppColors.border),
              ),
              ActionChip(
                label: const Text('Di atas Rp 200.000'),
                onPressed: () => _setPreset(200000, null),
                backgroundColor: AppColors.white,
                side: const BorderSide(color: AppColors.border),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          CustomTextField(
            label: 'Total minimal',
            hint: 'Tanpa batas',
            controller: _min,
            prefixText: 'Rp ',
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsSeparatorFormatter()],
          ),
          const SizedBox(height: AppSpacing.md),
          CustomTextField(
            label: 'Total maksimal',
            hint: 'Tanpa batas',
            controller: _max,
            prefixText: 'Rp ',
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsSeparatorFormatter()],
            errorText: _error,
          ),
          const SizedBox(height: AppSpacing.lg),
          CustomButton(
            label: 'Terapkan',
            icon: AppIcons.check,
            onPressed: _apply,
          ),
          const SizedBox(height: AppSpacing.sm),
          CustomButton(
            label: 'Hapus filter total',
            variant: CustomButtonVariant.secondary,
            onPressed: () =>
                Navigator.of(context).pop<TotalChoice>((min: null, max: null)),
          ),
        ],
      ),
    );
  }
}

// ============================================================== kategori

/// Memilih satu atau beberapa kategori. Mengembalikan null bila dibatalkan.
Future<Set<int>?> showCategoryFilterSheet(
  BuildContext context, {
  required List<CategoryModel> categories,
  required Set<int> selected,
}) {
  return _showSheet<Set<int>>(
    context,
    (BuildContext sheetContext) =>
        _CategoryFilterSheet(categories: categories, selected: selected),
  );
}

class _CategoryFilterSheet extends StatefulWidget {
  const _CategoryFilterSheet(
      {required this.categories, required this.selected});

  final List<CategoryModel> categories;
  final Set<int> selected;

  @override
  State<_CategoryFilterSheet> createState() => _CategoryFilterSheetState();
}

class _CategoryFilterSheetState extends State<_CategoryFilterSheet> {
  late final Set<int> _selected = Set<int>.of(widget.selected);

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: 'Filter kategori',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Struk ditampilkan bila kategori utamanya, atau salah satu barangnya, cocok.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final CategoryModel c in widget.categories)
                FilterChip(
                  label: Text(c.name),
                  selected: _selected.contains(c.id),
                  selectedColor: AppColors.emeraldTint,
                  checkmarkColor: AppColors.emeraldDeep,
                  backgroundColor: AppColors.white,
                  side: BorderSide(
                    color: _selected.contains(c.id)
                        ? AppColors.emerald
                        : AppColors.border,
                  ),
                  onSelected: (bool on) => setState(() {
                    final int? id = c.id;
                    if (id == null) return;
                    on ? _selected.add(id) : _selected.remove(id);
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          CustomButton(
            label: _selected.isEmpty
                ? 'Terapkan (semua kategori)'
                : 'Terapkan (${_selected.length} kategori)',
            icon: AppIcons.check,
            onPressed: () => Navigator.of(context).pop<Set<int>>(_selected),
          ),
          const SizedBox(height: AppSpacing.sm),
          CustomButton(
            label: 'Hapus pilihan',
            variant: CustomButtonVariant.secondary,
            onPressed: () => setState(_selected.clear),
          ),
        ],
      ),
    );
  }
}
