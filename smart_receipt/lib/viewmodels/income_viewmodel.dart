import 'package:flutter/foundation.dart';

import '../core/utils/month_utils.dart';
import '../data/models/income_model.dart';
import '../data/models/savings_models.dart';
import '../data/repositories/income_repository.dart';
import '../data/repositories/savings_repository.dart';
import '../services/income_service.dart';
import '../services/savings_planner.dart';
import 'auth_viewmodel.dart';
import 'safe_change_notifier.dart';

/// Hasil menambah pemasukan berulang.
class RecurringCreated {
  const RecurringCreated({required this.recurring, required this.created});

  final RecurringIncomeModel recurring;

  /// Pemasukan yang langsung dibuat (bulan-bulan yang sudah jatuh tempo).
  final List<IncomeModel> created;
}

/// Mengelola pemasukan: daftar, tambah/ubah/hapus, pemasukan berulang, dan
/// menyisihkan sebagian pemasukan ke target tabungan (saran alokasi).
class IncomeViewModel extends ChangeNotifier with SafeChangeNotifier {
  IncomeViewModel({
    required AuthViewModel authViewModel,
    required IncomeRepository incomeRepository,
    required SavingsRepository savingsRepository,
    required IncomeService incomeService,
    SavingsPlanner planner = const SavingsPlanner(),
    DateTime Function()? clock,
  })  : _auth = authViewModel,
        _incomes = incomeRepository,
        _savings = savingsRepository,
        _service = incomeService,
        _planner = planner,
        _clock = clock ?? DateTime.now;

  static const double maxAmount = 1e12;

  final AuthViewModel _auth;
  final IncomeRepository _incomes;
  final SavingsRepository _savings;
  final IncomeService _service;
  final SavingsPlanner _planner;
  final DateTime Function() _clock;

  List<IncomeModel> _list = <IncomeModel>[];
  List<RecurringIncomeModel> _recurring = <RecurringIncomeModel>[];
  List<GoalProgress> _goals = <GoalProgress>[];
  bool _loading = false;
  String? _error;

  List<IncomeModel> get incomes => _list;
  List<RecurringIncomeModel> get recurring => _recurring;

  /// Target yang masih berjalan (belum tercapai).
  List<GoalProgress> get activeGoals =>
      _goals.where((GoalProgress g) => g.isActive).toList();
  bool get isLoading => _loading;
  String? get errorMessage => _error;

  /// Nama target berdasarkan id (null bila sudah dihapus).
  String? goalNameOf(int id) {
    for (final GoalProgress g in _goals) {
      if (g.goal.id == id) return g.goal.name;
    }
    return null;
  }

  /// Total pemasukan pada bulan [month].
  double totalInMonth(DateTime month) {
    final String key = MonthUtils.key(month);
    return _list
        .where((IncomeModel i) => MonthUtils.key(i.date) == key)
        .fold<double>(0, (double s, IncomeModel i) => s + i.amount);
  }

  int? get _userId => _auth.currentUser?.id;

  void clearError() {
    if (_error == null) return;
    _error = null;
    safeNotify();
  }

  /// Memuat data; pemasukan berulang yang sudah jatuh tempo dibuat dulu.
  Future<void> load() async {
    final int? userId = _userId;
    if (userId == null) return;
    _loading = true;
    safeNotify();
    try {
      try {
        await _service.generateDue(userId, now: _clock());
      } catch (_) {
        // Gagal membuat pemasukan otomatis tidak menghalangi daftar tampil.
      }
      await _refresh(userId);
      _error = null;
    } catch (_) {
      _error = 'Gagal memuat pemasukan.';
    }
    _loading = false;
    safeNotify();
  }

  Future<void> _refresh(int userId) async {
    _list = await _incomes.getAll(userId);
    _recurring = await _incomes.getRecurring(userId);
    _goals =
        _planner.evaluateAll(await _savings.getGoals(userId), now: _clock());
  }

  // ------------------------------------------------------------ validasi

  String? _validate(String source, double amount) {
    if (source.trim().isEmpty) return 'Sumber pemasukan wajib diisi';
    if (source.trim().length > 40) return 'Sumber maksimal 40 karakter';
    if (amount <= 0) return 'Jumlah harus lebih dari 0';
    if (amount > maxAmount) return 'Jumlah terlalu besar';
    return null;
  }

  bool _fail(String message) {
    _error = message;
    safeNotify();
    return false;
  }

  // ----------------------------------------------------------- pemasukan

  /// Menyimpan pemasukan baru; mengembalikan data tersimpan (untuk menawarkan
  /// alokasi ke tabungan) atau null bila gagal.
  Future<IncomeModel?> addIncome({
    required String source,
    required double amount,
    required DateTime date,
    String? notes,
  }) async {
    final int? userId = _userId;
    if (userId == null) return null;
    final String? invalid = _validate(source, amount);
    if (invalid != null) {
      _fail(invalid);
      return null;
    }
    try {
      final IncomeModel saved = await _incomes.insert(
        IncomeModel(
          userId: userId,
          source: source.trim(),
          amount: amount,
          date: DateTime(date.year, date.month, date.day),
          notes: _cleanNotes(notes),
          createdAt: _clock(),
        ),
      );
      _error = null;
      await _refresh(userId);
      safeNotify();
      return saved;
    } catch (_) {
      _fail('Gagal menyimpan pemasukan.');
      return null;
    }
  }

  Future<bool> updateIncome(
    IncomeModel income, {
    required String source,
    required double amount,
    required DateTime date,
    String? notes,
  }) async {
    final int? userId = _userId;
    if (userId == null) return false;
    final String? invalid = _validate(source, amount);
    if (invalid != null) return _fail(invalid);
    try {
      await _incomes.update(
        income.copyWith(
          source: source.trim(),
          amount: amount,
          date: DateTime(date.year, date.month, date.day),
          notes: _cleanNotes(notes) ?? '',
        ),
      );
      _error = null;
      await _refresh(userId);
      safeNotify();
      return true;
    } catch (_) {
      return _fail('Gagal mengubah pemasukan.');
    }
  }

  Future<bool> deleteIncome(IncomeModel income) async {
    final int? userId = _userId;
    final int? id = income.id;
    if (userId == null || id == null) return false;
    try {
      await _incomes.delete(id);
      await _refresh(userId);
      safeNotify();
      return true;
    } catch (_) {
      return _fail('Gagal menghapus pemasukan.');
    }
  }

  String? _cleanNotes(String? notes) {
    final String text = (notes ?? '').trim();
    return text.isEmpty ? null : text;
  }

  // ------------------------------------------------------------ berulang

  /// Membuat pemasukan berulang dan langsung membuat bulan-bulan yang sudah
  /// jatuh tempo. [autoGoalId] dan [autoAmount] (opsional) menyetor otomatis
  /// ke target tiap pemasukan dibuat.
  Future<RecurringCreated?> addRecurring({
    required String source,
    required double amount,
    required DateTime startDate,
    String? notes,
    int? autoGoalId,
    double? autoAmount,
  }) async {
    final int? userId = _userId;
    if (userId == null) return null;
    final String? invalid = _validate(source, amount);
    if (invalid != null) {
      _fail(invalid);
      return null;
    }
    if (autoGoalId != null) {
      final double auto = autoAmount ?? 0;
      if (auto <= 0) {
        _fail('Jumlah yang disisihkan harus lebih dari 0');
        return null;
      }
      if (auto > amount) {
        _fail('Jumlah yang disisihkan tidak boleh melebihi pemasukan');
        return null;
      }
    }
    try {
      final RecurringIncomeModel saved = await _incomes.insertRecurring(
        RecurringIncomeModel(
          userId: userId,
          source: source.trim(),
          amount: amount,
          dayOfMonth: startDate.day,
          startMonth: MonthUtils.key(startDate),
          autoGoalId: autoGoalId,
          autoAmount: autoGoalId == null ? null : autoAmount,
          notes: _cleanNotes(notes),
          createdAt: _clock(),
        ),
      );
      final List<IncomeModel> created =
          await _service.generateDue(userId, now: _clock());
      _error = null;
      await _refresh(userId);
      safeNotify();
      return RecurringCreated(
        recurring: saved,
        created: created
            .where((IncomeModel i) => i.recurringId == saved.id)
            .toList(),
      );
    } catch (_) {
      _fail('Gagal menyimpan pemasukan berulang.');
      return null;
    }
  }

  Future<void> setRecurringActive(RecurringIncomeModel rec, bool active) async {
    final int? id = rec.id;
    final int? userId = _userId;
    if (id == null || userId == null) return;
    await _incomes.setRecurringActive(id, active);
    await _refresh(userId);
    safeNotify();
  }

  /// Menghapus aturan berulang; pemasukan yang sudah tercatat tetap ada.
  Future<void> deleteRecurring(RecurringIncomeModel rec) async {
    final int? id = rec.id;
    final int? userId = _userId;
    if (id == null || userId == null) return;
    await _incomes.deleteRecurring(id);
    await _refresh(userId);
    safeNotify();
  }

  // ---------------------------------------------------- alokasi tabungan

  /// Saran pembagian [amount] ke target yang masih berjalan.
  Map<int, double> suggestAllocation(double amount) =>
      _planner.suggestAllocation(activeGoals, amount);

  /// Menyisihkan sebagian [income] ke target-target ([amounts]: id target ->
  /// jumlah). Mengembalikan true bila berhasil; semuanya disimpan sekaligus.
  Future<bool> allocate(IncomeModel income, Map<int, double> amounts) async {
    final int? userId = _userId;
    final int? incomeId = income.id;
    if (userId == null || incomeId == null) return false;

    final Map<int, double> chosen = <int, double>{
      for (final MapEntry<int, double> e in amounts.entries)
        if (e.value > 0) e.key: e.value,
    };
    if (chosen.isEmpty) return true;

    final double total =
        chosen.values.fold<double>(0, (double a, double b) => a + b);
    if (total > income.amount + 0.5) {
      return _fail('Total yang disisihkan melebihi jumlah pemasukan');
    }
    try {
      final DateTime now = _clock();
      await _savings.insertDeposits(<SavingsDepositModel>[
        for (final MapEntry<int, double> e in chosen.entries)
          SavingsDepositModel(
            goalId: e.key,
            userId: userId,
            amount: e.value,
            date: income.date,
            incomeId: incomeId,
            notes: 'Disisihkan dari ${income.source}',
            createdAt: now,
          ),
      ]);
      _error = null;
      await _refresh(userId);
      safeNotify();
      return true;
    } catch (_) {
      return _fail('Gagal menyisihkan ke tabungan.');
    }
  }
}
