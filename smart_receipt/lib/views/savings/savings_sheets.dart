import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/thousands_separator_formatter.dart';
import '../../data/models/savings_models.dart';
import '../../services/savings_planner.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_textfield.dart';
import '../widgets/date_input_field.dart';
import '../widgets/sheet_frame.dart';

double? _parseAmount(String text) {
  final String digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : double.tryParse(digits);
}

// ================================================================= target

/// Isian formulir target tabungan.
class GoalInput {
  const GoalInput({
    required this.name,
    required this.targetAmount,
    this.deadline,
    this.notes,
  });

  final String name;
  final double targetAmount;
  final DateTime? deadline;
  final String? notes;
}

/// Formulir buat/ubah target. Mengembalikan null bila dibatalkan.
Future<GoalInput?> showGoalEditor(
  BuildContext context, {
  SavingsGoalModel? existing,
}) {
  return showAppSheet<GoalInput>(
    context,
    (BuildContext _) => _GoalEditor(existing: existing),
  );
}

class _GoalEditor extends StatefulWidget {
  const _GoalEditor({this.existing});

  final SavingsGoalModel? existing;

  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _target = TextEditingController(
    text: widget.existing == null
        ? ''
        : AppFormatters.amountInput(widget.existing!.targetAmount),
  );
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');

  /// Mengubah tanggal lewat kolom ketik membangun ulang kolomnya agar sinkron.
  int _dateKey = 0;
  late DateTime? _deadline = widget.existing?.deadline;
  String? _nameError;
  String? _targetError;
  String? _deadlineError;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime _today() {
    final DateTime n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  void _setDeadline(DateTime? value) => setState(() {
        _deadline = value;
        _deadlineError = null;
        _dateKey++;
      });

  /// Pratinjau: berapa yang perlu disisihkan tiap bulan.
  GoalProgress? _preview() {
    final double? target = _parseAmount(_target.text);
    if (target == null || target <= 0 || _deadline == null) return null;
    final SavingsGoalModel temp = SavingsGoalModel(
      userId: 0,
      name: 'x',
      targetAmount: target,
      deadline: _deadline,
      createdAt: widget.existing?.createdAt ?? _today(),
      savedAmount: widget.existing?.savedAmount ?? 0,
    );
    return const SavingsPlanner().evaluate(temp);
  }

  void _submit() {
    final String name = _name.text.trim();
    final double? target = _parseAmount(_target.text);
    setState(() {
      _nameError = name.isEmpty ? 'Nama target wajib diisi' : null;
      _targetError =
          (target == null || target <= 0) ? 'Target harus lebih dari 0' : null;
      _deadlineError =
          (!_isEdit && _deadline != null && _deadline!.isBefore(_today()))
              ? 'Tenggat tidak boleh sebelum hari ini'
              : null;
    });
    if (_nameError != null || _targetError != null || _deadlineError != null) {
      return;
    }
    Navigator.of(context).pop(
      GoalInput(
        name: name,
        targetAmount: target!,
        deadline: _deadline,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final GoalProgress? preview = _preview();
    final DateTime today = _today();

    return SheetFrame(
      title: _isEdit ? 'Ubah target' : 'Target tabungan baru',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomTextField(
            label: 'Nama target',
            hint: 'Contoh: Laptop baru',
            controller: _name,
            prefixIcon: AppIcons.piggyBank,
            textCapitalization: TextCapitalization.sentences,
            errorText: _nameError,
          ),
          const SizedBox(height: AppSpacing.md),
          CustomTextField(
            label: 'Jumlah target',
            hint: '0',
            controller: _target,
            prefixText: 'Rp ',
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsSeparatorFormatter()],
            errorText: _targetError,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Tenggat', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (String label, int months) in <(String, int)>[
                ('3 bulan', 3),
                ('6 bulan', 6),
                ('1 tahun', 12),
              ])
                ActionChip(
                  label: Text(label),
                  backgroundColor: AppColors.surface,
                  side: const BorderSide(color: AppColors.border),
                  onPressed: () => _setDeadline(
                    DateTime(today.year, today.month + months, today.day),
                  ),
                ),
              ActionChip(
                label: const Text('Tanpa tenggat'),
                backgroundColor:
                    _deadline == null ? AppColors.emeraldTint : AppColors.surface,
                side: BorderSide(
                  color:
                      _deadline == null ? AppColors.emerald : AppColors.border,
                ),
                onPressed: () => _setDeadline(null),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DateInputField(
            key: ValueKey<int>(_dateKey),
            label: 'Atau ketik tanggal tenggat',
            value: _deadline,
            errorText: _deadlineError,
            onChanged: (DateTime? d) => setState(() {
              _deadline = d;
              _deadlineError = null;
            }),
          ),
          if (preview != null && preview.requiredPerMonth != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.emeraldTint,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.lightbulb,
                      size: 18, color: AppColors.emeraldDeep),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Perlu menabung ${AppFormatters.rupiah(preview.requiredPerMonth!)} '
                      'per bulan selama ${preview.monthsLeft} bulan.',
                      style: textTheme.bodyMedium
                          ?.copyWith(color: AppColors.emeraldDeep),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          CustomTextField(
            label: 'Catatan (opsional)',
            hint: 'Tambahkan catatan',
            controller: _notes,
            maxLines: 2,
            keyboardType: TextInputType.multiline,
          ),
          const SizedBox(height: AppSpacing.lg),
          CustomButton(
            label: _isEdit ? 'Simpan perubahan' : 'Buat target',
            icon: AppIcons.check,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

// ================================================================ setoran

/// Isian setoran atau penarikan.
class DepositInput {
  const DepositInput({required this.amount, required this.date, this.notes});

  final double amount;
  final DateTime date;
  final String? notes;
}

/// Formulir setor/tarik. Mengembalikan null bila dibatalkan.
Future<DepositInput?> showDepositSheet(
  BuildContext context, {
  required SavingsGoalModel goal,
  bool withdraw = false,
  double? suggestion,
}) {
  return showAppSheet<DepositInput>(
    context,
    (BuildContext _) => _DepositSheet(
      goal: goal,
      withdraw: withdraw,
      suggestion: suggestion,
    ),
  );
}

class _DepositSheet extends StatefulWidget {
  const _DepositSheet({
    required this.goal,
    required this.withdraw,
    this.suggestion,
  });

  final SavingsGoalModel goal;
  final bool withdraw;
  final double? suggestion;

  @override
  State<_DepositSheet> createState() => _DepositSheetState();
}

class _DepositSheetState extends State<_DepositSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.suggestion == null || widget.withdraw
        ? ''
        : AppFormatters.amountInput(widget.suggestion!),
  );
  final TextEditingController _notes = TextEditingController();
  DateTime? _date = () {
    final DateTime n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }();
  String? _amountError;
  String? _dateError;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final double? amount = _parseAmount(_amount.text);
    final DateTime? date = _date;
    String? amountError;
    if (amount == null || amount <= 0) {
      amountError = 'Jumlah harus lebih dari 0';
    } else if (widget.withdraw && amount > widget.goal.savedAmount + 0.5) {
      amountError =
          'Melebihi tabungan (${AppFormatters.rupiah(widget.goal.savedAmount)})';
    }
    setState(() {
      _amountError = amountError;
      _dateError = date == null ? 'Tanggal belum valid' : null;
    });
    if (amountError != null || date == null) return;
    Navigator.of(context).pop(
      DepositInput(
        amount: amount!,
        date: date,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool out = widget.withdraw;
    return SheetFrame(
      title: out
          ? 'Tarik dari "${widget.goal.name}"'
          : 'Setor ke "${widget.goal.name}"',
      subtitle: out
          ? 'Tabungan saat ini ${AppFormatters.rupiah(widget.goal.savedAmount)}. '
              'Uang yang ditarik kembali menjadi sisa uang bebas.'
          : 'Sisa target ${AppFormatters.rupiah(widget.goal.remaining)}. '
              'Setoran bukan pengeluaran, hanya memindahkan uang ke tabungan.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomTextField(
            label: 'Jumlah',
            hint: '0',
            controller: _amount,
            prefixText: 'Rp ',
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandsSeparatorFormatter()],
            errorText: _amountError,
          ),
          const SizedBox(height: AppSpacing.md),
          DateInputField(
            label: 'Tanggal (hari, bulan, tahun)',
            value: _date,
            errorText: _dateError,
            onChanged: (DateTime? d) => setState(() {
              _date = d;
              _dateError = null;
            }),
          ),
          const SizedBox(height: AppSpacing.md),
          CustomTextField(
            label: 'Catatan (opsional)',
            hint: 'Tambahkan catatan',
            controller: _notes,
          ),
          const SizedBox(height: AppSpacing.lg),
          CustomButton(
            label: out ? 'Tarik' : 'Setor',
            icon: AppIcons.check,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
