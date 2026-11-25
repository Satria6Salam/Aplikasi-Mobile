import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_icons.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/thousands_separator_formatter.dart';
import '../../data/models/income_model.dart';
import '../../services/savings_planner.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_textfield.dart';
import '../widgets/date_input_field.dart';
import '../widgets/sheet_frame.dart';

/// Isian formulir pemasukan.
class IncomeEditorResult {
  const IncomeEditorResult({
    required this.source,
    required this.amount,
    required this.date,
    this.notes,
    this.recurring = false,
    this.autoGoalId,
    this.autoAmount,
    this.delete = false,
  });

  final String source;
  final double amount;
  final DateTime date;
  final String? notes;

  /// True bila dicatat otomatis tiap bulan (hanya saat membuat baru).
  final bool recurring;

  /// Target yang otomatis disetori tiap pemasukan berulang dibuat.
  final int? autoGoalId;
  final double? autoAmount;

  /// True bila pengguna memilih menghapus pemasukan yang sedang diubah.
  final bool delete;
}

/// Formulir catat/ubah pemasukan. Mengembalikan null bila dibatalkan.
Future<IncomeEditorResult?> showIncomeEditor(
  BuildContext context, {
  IncomeModel? existing,
  List<GoalProgress> goals = const <GoalProgress>[],
}) {
  return showAppSheet<IncomeEditorResult>(
    context,
    (BuildContext _) => _IncomeEditor(existing: existing, goals: goals),
  );
}

class _IncomeEditor extends StatefulWidget {
  const _IncomeEditor({this.existing, required this.goals});

  final IncomeModel? existing;
  final List<GoalProgress> goals;

  @override
  State<_IncomeEditor> createState() => _IncomeEditorState();
}

class _IncomeEditorState extends State<_IncomeEditor> {
  static const List<String> _presets = <String>[
    'Uang saku',
    'Gaji',
    'Freelance',
    'Hadiah',
    'Lainnya',
  ];

  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : AppFormatters.amountInput(widget.existing!.amount),
  );
  late final TextEditingController _source =
      TextEditingController(text: widget.existing?.source ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  final TextEditingController _autoAmount = TextEditingController();

  late DateTime? _date = widget.existing?.date ?? _today();
  bool _recurring = false;
  bool _auto = false;
  int? _goalId;

  String? _amountError;
  String? _sourceError;
  String? _dateError;
  String? _autoError;

  bool get _isEdit => widget.existing != null;

  static DateTime _today() {
    final DateTime n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    if (widget.goals.isNotEmpty) _goalId = widget.goals.first.goal.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _source.dispose();
    _notes.dispose();
    _autoAmount.dispose();
    super.dispose();
  }

  double? _parse(String text) {
    final String digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : double.tryParse(digits);
  }

  void _submit() {
    final double? amount = _parse(_amount.text);
    final String source = _source.text.trim();
    final DateTime? date = _date;
    double? auto;
    String? autoError;
    if (_recurring && _auto) {
      auto = _parse(_autoAmount.text);
      if (auto == null || auto <= 0) {
        autoError = 'Isi jumlah yang disisihkan';
      } else if (amount != null && auto > amount) {
        autoError = 'Tidak boleh melebihi pemasukan';
      }
    }

    setState(() {
      _amountError =
          (amount == null || amount <= 0) ? 'Jumlah harus lebih dari 0' : null;
      _sourceError = source.isEmpty ? 'Sumber wajib diisi' : null;
      _dateError = date == null ? 'Tanggal belum valid' : null;
      _autoError = autoError;
    });
    if (_amountError != null ||
        _sourceError != null ||
        _dateError != null ||
        _autoError != null) {
      return;
    }

    Navigator.of(context).pop(
      IncomeEditorResult(
        source: source,
        amount: amount!,
        date: date!,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        recurring: _recurring,
        autoGoalId: _recurring && _auto ? _goalId : null,
        autoAmount: _recurring && _auto ? auto : null,
      ),
    );
  }

  Future<void> _delete() async {
    final bool ok = await showConfirmDialog(
      context,
      title: 'Hapus pemasukan?',
      message: 'Pemasukan ini akan dihapus. Setoran tabungan yang pernah '
          'disisihkan darinya tetap tersimpan di targetnya.',
      confirmLabel: 'Hapus',
      isDestructive: true,
    );
    if (!ok || !mounted) return;
    final IncomeModel e = widget.existing!;
    Navigator.of(context).pop(
      IncomeEditorResult(
        source: e.source,
        amount: e.amount,
        date: e.date,
        delete: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final DateTime? date = _date;

    return SheetFrame(
      title: _isEdit ? 'Ubah pemasukan' : 'Catat pemasukan',
      subtitle: _isEdit && widget.existing!.isAutomatic
          ? 'Dibuat otomatis dari pemasukan berulang.'
          : null,
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
          CustomTextField(
            label: 'Sumber',
            hint: 'Contoh: Uang saku',
            controller: _source,
            prefixIcon: AppIcons.wallet,
            textCapitalization: TextCapitalization.sentences,
            errorText: _sourceError,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final String preset in _presets)
                ActionChip(
                  label: Text(preset),
                  backgroundColor: AppColors.surface,
                  side: const BorderSide(color: AppColors.border),
                  onPressed: () => setState(() {
                    _source.text = preset;
                    _sourceError = null;
                  }),
                ),
            ],
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
            maxLines: 2,
            keyboardType: TextInputType.multiline,
          ),
          if (!_isEdit) ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _recurring,
              activeThumbColor: AppColors.emerald,
              title: const Text('Berulang tiap bulan'),
              subtitle: Text(
                date == null
                    ? 'Pilih tanggal dulu'
                    : 'Dicatat otomatis tiap tanggal ${date.day}'
                        '${date.day > 28 ? ' (bulan pendek memakai tanggal terakhir)' : ''}.',
                style: textTheme.bodySmall,
              ),
              onChanged: (bool v) => setState(() => _recurring = v),
            ),
            if (_recurring && widget.goals.isNotEmpty) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _auto,
                activeThumbColor: AppColors.emerald,
                title: const Text('Otomatis sisihkan ke target'),
                subtitle: Text(
                  'Setiap pemasukan ini tercatat, sebagian langsung masuk tabungan.',
                  style: textTheme.bodySmall,
                ),
                onChanged: (bool v) => setState(() => _auto = v),
              ),
              if (_auto) ...[
                DropdownButtonFormField<int>(
                  initialValue: _goalId,
                  decoration: const InputDecoration(labelText: 'Target'),
                  items: [
                    for (final GoalProgress g in widget.goals)
                      DropdownMenuItem<int>(
                        value: g.goal.id,
                        child:
                            Text(g.goal.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (int? v) => setState(() => _goalId = v),
                ),
                const SizedBox(height: AppSpacing.md),
                CustomTextField(
                  label: 'Disisihkan tiap bulan',
                  hint: '0',
                  controller: _autoAmount,
                  prefixText: 'Rp ',
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsSeparatorFormatter()],
                  errorText: _autoError,
                ),
              ],
            ],
          ],
          const SizedBox(height: AppSpacing.lg),
          CustomButton(
            label: _isEdit ? 'Simpan perubahan' : 'Simpan',
            icon: AppIcons.check,
            onPressed: _submit,
          ),
          if (_isEdit) ...[
            const SizedBox(height: 8),
            CustomButton(
              label: 'Hapus pemasukan',
              icon: AppIcons.trash,
              variant: CustomButtonVariant.danger,
              onPressed: _delete,
            ),
          ],
        ],
      ),
    );
  }
}
