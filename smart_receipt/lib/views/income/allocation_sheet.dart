import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/thousands_separator_formatter.dart';
import '../../data/models/income_model.dart';
import '../../services/savings_planner.dart';
import '../widgets/custom_button.dart';
import '../widgets/sheet_frame.dart';

/// "Sisihkan untuk target?": ditampilkan setelah mencatat pemasukan. Jumlah
/// awalnya diisi dari kebutuhan per bulan tiap target, dan pengguna bebas
/// mengubah atau melewatinya. Mengembalikan id target -> jumlah (hanya yang
/// lebih dari 0), atau null bila dilewati.
Future<Map<int, double>?> showAllocationSheet(
  BuildContext context, {
  required IncomeModel income,
  required List<GoalProgress> goals,
  required Map<int, double> suggestions,
}) {
  return showAppSheet<Map<int, double>>(
    context,
    (BuildContext _) => _AllocationSheet(
      income: income,
      goals: goals,
      suggestions: suggestions,
    ),
  );
}

class _AllocationSheet extends StatefulWidget {
  const _AllocationSheet({
    required this.income,
    required this.goals,
    required this.suggestions,
  });

  final IncomeModel income;
  final List<GoalProgress> goals;
  final Map<int, double> suggestions;

  @override
  State<_AllocationSheet> createState() => _AllocationSheetState();
}

class _AllocationSheetState extends State<_AllocationSheet> {
  final Map<int, TextEditingController> _controllers =
      <int, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final GoalProgress g in widget.goals) {
      final int? id = g.goal.id;
      if (id == null) continue;
      final double? suggested = widget.suggestions[id];
      _controllers[id] = TextEditingController(
        text: suggested == null ? '' : AppFormatters.amountInput(suggested),
      );
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _amountOf(int id) {
    final String digits =
        (_controllers[id]?.text ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? 0 : (double.tryParse(digits) ?? 0);
  }

  double get _total => _controllers.keys
      .fold<double>(0, (double s, int id) => s + _amountOf(id));

  String? _errorOf(GoalProgress g) {
    final int? id = g.goal.id;
    if (id == null) return null;
    final double v = _amountOf(id);
    if (v > g.goal.remaining + 0.5) {
      return 'Melebihi sisa target (${AppFormatters.rupiah(g.goal.remaining)})';
    }
    return null;
  }

  bool get _valid =>
      _total <= widget.income.amount + 0.5 &&
      widget.goals.every((GoalProgress g) => _errorOf(g) == null);

  void _confirm() {
    if (!_valid) return;
    Navigator.of(context).pop(<int, double>{
      for (final int id in _controllers.keys)
        if (_amountOf(id) > 0) id: _amountOf(id),
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final double income = widget.income.amount;
    final double left = income - _total;
    final bool over = left < -0.5;

    return SheetFrame(
      title: 'Sisihkan untuk target?',
      subtitle:
          '${AppFormatters.rupiah(income)} dari ${widget.income.source} baru dicatat. '
          'Jumlah di bawah diusulkan dari kebutuhan tiap target per bulan; ubah sesuka Anda.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final GoalProgress g in widget.goals)
            if (g.goal.id != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(AppIcons.piggyBank,
                            size: 18, color: AppColors.emerald),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(g.goal.name,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sisa ${AppFormatters.rupiah(g.goal.remaining)}'
                      '${g.requiredPerMonth == null ? '' : ' · butuh ${AppFormatters.rupiah(g.requiredPerMonth!)}/bulan'}',
                      style: textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _controllers[g.goal.id],
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsSeparatorFormatter()],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixText: 'Rp ',
                        hintText: '0',
                        errorText: _errorOf(g),
                      ),
                    ),
                  ],
                ),
              ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: over ? AppColors.errorTint : AppColors.emeraldTint,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text('Disisihkan', style: textTheme.bodyMedium)),
                    Text(AppFormatters.rupiah(_total),
                        style: AppTextStyles.amount(size: 15)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        over ? 'Melebihi pemasukan' : 'Sisa untuk Anda',
                        style: textTheme.bodyMedium?.copyWith(
                          color: over ? AppColors.error : null,
                        ),
                      ),
                    ),
                    Text(
                      AppFormatters.rupiah(left),
                      style: AppTextStyles.amount(
                        size: 15,
                        color: over ? AppColors.error : AppColors.emeraldDeep,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          CustomButton(
            label: 'Sisihkan',
            icon: AppIcons.check,
            onPressed: _valid ? _confirm : null,
          ),
          const SizedBox(height: 8),
          CustomButton(
            label: 'Lewati',
            variant: CustomButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
