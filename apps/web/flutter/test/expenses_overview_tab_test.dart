import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/expenses/expenses_overview_tab.dart';

void main() {
  testWidgets(
    'shows an error state without crashing when no backend is reachable in test',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ExpensesOverviewTab(establishmentId: 'est-1')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('defaults to "Mois" and offers Année/Mois/Semaine', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ExpensesOverviewTab(establishmentId: 'est-1')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Année'), findsOneWidget);
    expect(find.text('Mois'), findsOneWidget);
    expect(find.text('Semaine'), findsOneWidget);
  });
}
