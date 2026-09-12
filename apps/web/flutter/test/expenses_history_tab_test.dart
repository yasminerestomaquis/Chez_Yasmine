import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/expenses/expenses_history_tab.dart';

void main() {
  testWidgets('shows a "Filtrer" action and an "Exporter Excel" button', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ExpensesHistoryTab(establishmentId: 'est-1')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Filtrer'), findsOneWidget);
    expect(find.text('Exporter Excel'), findsOneWidget);
  });
}
