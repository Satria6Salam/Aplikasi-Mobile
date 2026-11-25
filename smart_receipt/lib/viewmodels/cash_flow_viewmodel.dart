import 'package:flutter/foundation.dart';

import '../core/utils/dashboard_period.dart';
import '../services/cash_flow_service.dart';
import 'auth_viewmodel.dart';
import 'safe_change_notifier.dart';

/// Data kartu Arus Kas di Dasbor: pemasukan, pengeluaran, tabungan, dan sisa
/// pada periode yang dilihat, plus tren enam bulan.
class CashFlowViewModel extends ChangeNotifier with SafeChangeNotifier {
  CashFlowViewModel({
    required AuthViewModel authViewModel,
    required CashFlowService service,
    DateTime Function()? clock,
  })  : _auth = authViewModel,
        _service = service,
        _clock = clock ?? DateTime.now;

  /// Jumlah bulan pada grafik tren.
  static const int trendMonths = 6;

  final AuthViewModel _auth;
  final CashFlowService _service;
  final DateTime Function() _clock;

  DashboardPeriod? _period;
  CashFlow _flow = CashFlow.zero;
  List<MonthCashFlow> _trend = <MonthCashFlow>[];
  bool _loading = false;
  bool _failed = false;
  int _token = 0;

  CashFlow get flow => _flow;
  List<MonthCashFlow> get trend => _trend;
  bool get isLoading => _loading;
  bool get hasFailed => _failed;

  /// True bila ada pemasukan, pengeluaran, atau tabungan pada tren maupun periode.
  bool get hasAnyData =>
      _flow.hasData || _trend.any((MonthCashFlow m) => m.flow.hasData);

  /// Bulan terakhir pada grafik tren untuk [period].
  DateTime trendEnd(DashboardPeriod period) {
    final DateTime now = _clock();
    switch (period.mode) {
      case PeriodMode.day:
      case PeriodMode.month:
        return DateTime(period.anchor.year, period.anchor.month);
      case PeriodMode.year:
        return period.anchor.year == now.year
            ? DateTime(now.year, now.month)
            : DateTime(period.anchor.year, 12);
    }
  }

  /// Memuat ulang periode terakhir (mis. setelah kembali dari layar Pemasukan).
  Future<void> reload() async {
    final DashboardPeriod? period = _period;
    if (period != null) await load(period);
  }

  Future<void> load(DashboardPeriod period) async {
    _period = period;
    final int? userId = _auth.currentUser?.id;
    if (userId == null) {
      _flow = CashFlow.zero;
      _trend = <MonthCashFlow>[];
      safeNotify();
      return;
    }
    final int token = ++_token;
    _loading = true;
    safeNotify();
    try {
      final CashFlow flow =
          await _service.forRange(userId, period.start, period.endExclusive);
      final List<MonthCashFlow> trend = await _service.lastMonths(
        userId,
        trendMonths,
        now: trendEnd(period),
      );
      if (token != _token) return; // Ada pemuatan yang lebih baru.
      _flow = flow;
      _trend = trend;
      _failed = false;
    } catch (_) {
      if (token != _token) return;
      _failed = true;
    }
    _loading = false;
    safeNotify();
  }
}
