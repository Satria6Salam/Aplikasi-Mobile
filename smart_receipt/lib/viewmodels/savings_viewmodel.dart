import 'package:flutter/foundation.dart';

import '../data/models/savings_models.dart';
import '../data/repositories/savings_repository.dart';
import '../core/utils/month_utils.dart';
import '../services/cash_flow_service.dart';
import '../services/savings_planner.dart';
import 'auth_viewmodel.dart';
import 'safe_change_notifier.dart';

/// Apakah semua target berjalan masuk akal dengan kemampuan bulan ini.
enum RealityCheck {
  /// Belum bisa dinilai (belum ada target bertenggat atau pemasukan bulan ini).
  unknown,

  /// Sisa uang bulan ini cukup untuk semua target.
  realistic,

  /// Sisa uang bulan ini tidak cukup untuk semua target.
  shortfall,
}

/// Mengelola target tabungan: buat/ubah/hapus target, setor, dan tarik.
class SavingsViewModel extends ChangeNotifier with SafeChangeNotifier {
  SavingsViewModel({
    required AuthViewModel authViewModel,
    required SavingsRepository savingsRepository,
    SavingsPlanner planner = const SavingsPlanner(),
    CashFlowService? cashFlowService,
    DateTime Function()? clock,
  })  : _auth = authViewModel,
        _repository = savingsRepository,
        _cashFlow = cashFlowService,
        _planner = planner,
        _clock = clock ?? DateTime.now;

  static const double maxAmount = 1e12;

  final AuthViewModel _auth;
  final SavingsRepository _repository;
  final SavingsPlanner _planner;
  final CashFlowService? _cashFlow;
  final DateTime Function() _clock;

  CashFlow? _monthFlow;
  List<GoalProgress> _goals = <GoalProgress>[];
  bool _loading = false;
  String? _error;

  /// Semua target (yang masih berjalan lebih dulu, lalu yang sudah tercapai).
  List<GoalProgress> get goals => _goals;
  List<GoalProgress> get activeGoals =>
      _goals.where((GoalProgress g) => g.isActive).toList();
  List<GoalProgress> get completedGoals =>
      _goals.where((GoalProgress g) => !g.isActive).toList();
  bool get isLoading => _loading;
  String? get errorMessage => _error;

  /// Total yang sedang tersimpan di semua target.
  double get totalSaved => _goals.fold<double>(
      0, (double s, GoalProgress g) => s + g.goal.savedAmount);

  /// Kebutuhan setoran per bulan untuk semua target berjalan bertenggat.
  double get totalRequiredPerMonth => activeGoals.fold<double>(
      0, (double s, GoalProgress g) => s + (g.requiredPerMonth ?? 0));

  /// Arus kas bulan ini (null bila tidak tersedia).
  CashFlow? get monthFlow => _monthFlow;

  /// Uang yang bisa ditabung bulan ini: pemasukan dikurangi pengeluaran
  /// (sebelum disisihkan). Perkiraan, karena bulan belum berakhir.
  double get monthlyCapacity {
    final CashFlow? flow = _monthFlow;
    return flow == null ? 0 : flow.income - flow.expense;
  }

  /// Kekurangan per bulan agar semua target tepat waktu (positif = kurang).
  double get monthlyGap => totalRequiredPerMonth - monthlyCapacity;

  RealityCheck get realityCheck {
    final CashFlow? flow = _monthFlow;
    if (flow == null || flow.income <= 0 || totalRequiredPerMonth <= 0) {
      return RealityCheck.unknown;
    }
    return monthlyGap <= 0.5 ? RealityCheck.realistic : RealityCheck.shortfall;
  }

  int? get _userId => _auth.currentUser?.id;

  void clearError() {
    if (_error == null) return;
    _error = null;
    safeNotify();
  }

  Future<void> load() async {
    final int? userId = _userId;
    if (userId == null) return;
    _loading = true;
    safeNotify();
    try {
      await _refresh(userId);
      _error = null;
    } catch (_) {
      _error = 'Gagal memuat target tabungan.';
    }
    _loading = false;
    safeNotify();
  }

  Future<void> _refresh(int userId) async {
    final List<GoalProgress> all = _planner.evaluateAll(
      await _repository.getGoals(userId),
      now: _clock(),
    );
    // Target berjalan di atas, yang tercapai di bawah (urutan lain dipertahankan).
    _goals = <GoalProgress>[
      ...all.where((GoalProgress g) => g.isActive),
      ...all.where((GoalProgress g) => !g.isActive),
    ];

    final CashFlowService? cashFlow = _cashFlow;
    if (cashFlow != null) {
      final DateTime now = _clock();
      try {
        _monthFlow = await cashFlow.forRange(
          userId,
          MonthUtils.startOf(now),
          MonthUtils.endExclusive(now),
        );
      } catch (_) {
        _monthFlow = null; // Penilaian realistis dilewati, daftar tetap tampil.
      }
    }
  }

  bool _fail(String message) {
    _error = message;
    safeNotify();
    return false;
  }

  // ------------------------------------------------------------- target

  String? _validateGoal(String name, double target, DateTime? deadline,
      {required bool newGoal}) {
    if (name.trim().isEmpty) return 'Nama target wajib diisi';
    if (name.trim().length > 60) return 'Nama maksimal 60 karakter';
    if (target <= 0) return 'Target harus lebih dari 0';
    if (target > maxAmount) return 'Target terlalu besar';
    if (newGoal && deadline != null) {
      final DateTime now = _clock();
      final DateTime today = DateTime(now.year, now.month, now.day);
      if (deadline.isBefore(today)) {
        return 'Tenggat tidak boleh sebelum hari ini';
      }
    }
    return null;
  }

  Future<bool> addGoal({
    required String name,
    required double targetAmount,
    DateTime? deadline,
    String? notes,
  }) async {
    final int? userId = _userId;
    if (userId == null) return false;
    final String? invalid =
        _validateGoal(name, targetAmount, deadline, newGoal: true);
    if (invalid != null) return _fail(invalid);
    try {
      await _repository.insertGoal(
        SavingsGoalModel(
          userId: userId,
          name: name.trim(),
          targetAmount: targetAmount,
          deadline: deadline == null
              ? null
              : DateTime(deadline.year, deadline.month, deadline.day),
          notes: _clean(notes),
          createdAt: _clock(),
        ),
      );
      _error = null;
      await _refresh(userId);
      safeNotify();
      return true;
    } catch (_) {
      return _fail('Gagal menyimpan target.');
    }
  }

  Future<bool> updateGoal(
    SavingsGoalModel goal, {
    required String name,
    required double targetAmount,
    DateTime? deadline,
    String? notes,
  }) async {
    final int? userId = _userId;
    if (userId == null) return false;
    final String? invalid =
        _validateGoal(name, targetAmount, deadline, newGoal: false);
    if (invalid != null) return _fail(invalid);
    try {
      await _repository.updateGoal(
        goal.copyWith(
          name: name.trim(),
          targetAmount: targetAmount,
          deadline: deadline == null
              ? null
              : DateTime(deadline.year, deadline.month, deadline.day),
          clearDeadline: deadline == null,
          notes: _clean(notes) ?? '',
        ),
      );
      _error = null;
      await _refresh(userId);
      safeNotify();
      return true;
    } catch (_) {
      return _fail('Gagal mengubah target.');
    }
  }

  /// Menghapus target beserta seluruh riwayat setorannya.
  Future<bool> deleteGoal(SavingsGoalModel goal) async {
    final int? userId = _userId;
    final int? id = goal.id;
    if (userId == null || id == null) return false;
    try {
      await _repository.deleteGoal(id);
      await _refresh(userId);
      safeNotify();
      return true;
    } catch (_) {
      return _fail('Gagal menghapus target.');
    }
  }

  String? _clean(String? text) {
    final String t = (text ?? '').trim();
    return t.isEmpty ? null : t;
  }

  // ------------------------------------------------------------- setoran

  Future<List<SavingsDepositModel>> depositsOf(SavingsGoalModel goal) async {
    final int? id = goal.id;
    if (id == null) return <SavingsDepositModel>[];
    return _repository.getDeposits(id);
  }

  Future<bool> deposit(
    SavingsGoalModel goal, {
    required double amount,
    DateTime? date,
    String? notes,
  }) {
    if (amount <= 0) {
      return Future<bool>.value(_fail('Jumlah harus lebih dari 0'));
    }
    if (amount > maxAmount) {
      return Future<bool>.value(_fail('Jumlah terlalu besar'));
    }
    return _record(goal, amount, date, notes);
  }

  /// Menarik tabungan (misalnya dipakai membeli barangnya). Tidak boleh
  /// melebihi jumlah yang sudah tertabung.
  Future<bool> withdraw(
    SavingsGoalModel goal, {
    required double amount,
    DateTime? date,
    String? notes,
  }) {
    if (amount <= 0) {
      return Future<bool>.value(_fail('Jumlah harus lebih dari 0'));
    }
    if (amount > goal.savedAmount + 0.5) {
      return Future<bool>.value(
          _fail('Penarikan melebihi tabungan yang ada di target ini'));
    }
    return _record(goal, -amount, date, notes ?? 'Penarikan');
  }

  Future<bool> _record(
    SavingsGoalModel goal,
    double signedAmount,
    DateTime? date,
    String? notes,
  ) async {
    final int? userId = _userId;
    final int? goalId = goal.id;
    if (userId == null || goalId == null) return false;
    final DateTime now = _clock();
    final DateTime when = date ?? now;
    try {
      await _repository.insertDeposit(
        SavingsDepositModel(
          goalId: goalId,
          userId: userId,
          amount: signedAmount,
          date: DateTime(when.year, when.month, when.day),
          notes: _clean(notes),
          createdAt: now,
        ),
      );
      _error = null;
      await _refresh(userId);
      safeNotify();
      return true;
    } catch (_) {
      return _fail('Gagal menyimpan setoran.');
    }
  }

  Future<bool> deleteDeposit(SavingsDepositModel deposit) async {
    final int? userId = _userId;
    final int? id = deposit.id;
    if (userId == null || id == null) return false;
    try {
      await _repository.deleteDeposit(id);
      await _refresh(userId);
      safeNotify();
      return true;
    } catch (_) {
      return _fail('Gagal menghapus setoran.');
    }
  }
}
