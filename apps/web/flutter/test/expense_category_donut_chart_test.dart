import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/expenses/expense_category_donut_chart.dart';
import 'package:chez_yasmine/expenses/expense_summary_models.dart';

void main() {
  testWidgets('shows an empty state when there is no data', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ExpenseCategoryDonutChart(items: [])),
      ),
    );
    expect(find.text('Aucune donnée pour cette période'), findsOneWidget);
  });

  testWidgets('shows one legend entry per category with its percentage', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpenseCategoryDonutChart(
            items: [
              ExpenseCategoryAmount(category: 'Salaires', amount: 620000),
              ExpenseCategoryAmount(category: 'Marché', amount: 280000),
            ],
          ),
        ),
      ),
    );
    expect(find.textContaining('Salaires'), findsOneWidget);
    expect(
      find.textContaining('69'),
      findsOneWidget,
    ); // 620000 / 900000 ≈ 68.9%
  });
}
