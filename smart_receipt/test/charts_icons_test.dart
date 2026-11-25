import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smart_receipt/core/theme/app_colors.dart';
import 'package:smart_receipt/services/insight_service.dart';
import 'package:smart_receipt/views/widgets/bar_trend_chart.dart';
import 'package:smart_receipt/views/widgets/donut_chart.dart';
import 'package:smart_receipt/views/widgets/duotone_icon.dart';
import 'package:smart_receipt/views/widgets/price_line_chart.dart';
import 'package:smart_receipt/views/widgets/spending_trend_chart.dart';

Widget host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 320, child: child),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  testWidgets('DuotoneIcon menampilkan ikon pada ukuran yang diminta',
      (tester) async {
    await tester.pumpWidget(host(const Align(
      alignment: Alignment.topLeft,
      child: DuotoneIcon(
        icon: Icons.wallet,
        color: AppColors.emerald,
        size: 46,
      ),
    )));

    expect(find.byIcon(Icons.wallet), findsOneWidget);
    expect(tester.getSize(find.byType(DuotoneIcon)), const Size(46, 46));
  });

  testWidgets('DuotoneIcon varian gelap tidak error', (tester) async {
    await tester.pumpWidget(host(const DuotoneIcon(
      icon: Icons.qr_code,
      color: AppColors.white,
      accent: AppColors.lime,
      onDark: true,
    )));

    expect(tester.takeException(), isNull);
  });

  testWidgets('grafik batang tren: ketuk batang menampilkan nilainya',
      (tester) async {
    int? opened;
    await tester.pumpWidget(host(BarTrendChart(
      bars: const [
        TrendBar(label: 'J', caption: 'Januari', amount: 100000),
        TrendBar(
            label: 'F',
            caption: 'Februari',
            amount: 250000,
            isHighlighted: true),
        TrendBar(label: 'M', caption: 'Maret', amount: 0),
      ],
      onOpen: (int i) => opened = i,
    )));
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.text('F'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Februari'), findsOneWidget);
    await tester.tap(find.text('Lihat'));
    expect(opened, 1);
  });

  testWidgets('grafik harian dan donat tampil tanpa galat', (tester) async {
    await tester.pumpWidget(host(Column(children: const [
      SpendingTrendChart(data: [
        DailySpending(day: 1, amount: 10000),
        DailySpending(day: 2, amount: 0),
        DailySpending(day: 3, amount: 45000),
      ]),
      DonutChart(
        slices: [
          DonutSlice(value: 60, color: AppColors.emerald),
          DonutSlice(value: 40, color: AppColors.warning),
        ],
        centerTop: 'Rp100',
        centerBottom: 'total',
      ),
    ])));
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
    expect(find.text('Rp100'), findsOneWidget);
  });

  testWidgets('donat satu irisan dan grafik harga satu titik tidak error',
      (tester) async {
    await tester.pumpWidget(host(Column(children: [
      const DonutChart(
        slices: [DonutSlice(value: 5, color: AppColors.emerald)],
        centerTop: 'A',
        centerBottom: 'b',
      ),
      PriceLineChart(points: [
        PricePoint(date: DateTime(2026, 11, 1), price: 12000),
      ]),
    ])));
    await tester.pump(const Duration(seconds: 2));

    expect(tester.takeException(), isNull);
  });

  testWidgets('grafik harga beberapa titik dengan lengkung tidak error',
      (tester) async {
    await tester.pumpWidget(host(PriceLineChart(points: [
      PricePoint(date: DateTime(2026, 9, 1), price: 12000),
      PricePoint(date: DateTime(2026, 10, 1), price: 15500),
      PricePoint(date: DateTime(2026, 11, 1), price: 13000),
    ])));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
