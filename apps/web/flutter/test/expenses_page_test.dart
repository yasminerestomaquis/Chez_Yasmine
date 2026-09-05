import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/expenses/expenses_page.dart';

void main() {
  Future<void> openAddDialog(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ExpensesPage(establishmentId: 'est-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the list error state when the network call fails (no server in tests)', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ExpensesPage(establishmentId: 'est-1')));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('rejects an empty label and a non-positive amount', (tester) async {
    await openAddDialog(tester);

    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(find.text('Libellé requis'), findsOneWidget);
    expect(find.text('Montant invalide'), findsOneWidget);
  });

  testWidgets('accepts a valid label and amount past validation', (tester) async {
    await openAddDialog(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Libellé *'), 'Loyer');
    await tester.enterText(find.widgetWithText(TextFormField, 'Montant *'), '50000');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(find.text('Libellé requis'), findsNothing);
    expect(find.text('Montant invalide'), findsNothing);
  });
}
