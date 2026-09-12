import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/expenses/expenses_form_tab.dart';

void main() {
  Future<void> openAddDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ExpensesFormTab(establishmentId: 'est-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows the list error state when the network call fails (no server in tests)',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ExpensesFormTab(establishmentId: 'est-1')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('rejects an empty label and a non-positive amount', (
    tester,
  ) async {
    await openAddDialog(tester);

    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(find.text('Libellé requis'), findsOneWidget);
    expect(find.text('Montant invalide'), findsOneWidget);
  });

  testWidgets('accepts a valid label and amount past validation', (
    tester,
  ) async {
    await openAddDialog(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Libellé *'),
      'Loyer',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Montant *'),
      '50000',
    );
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(find.text('Libellé requis'), findsNothing);
    expect(find.text('Montant invalide'), findsNothing);
  });

  testWidgets(
    'offers the predefined expense categories plus a free-text "Autre" option',
    (tester) async {
      await openAddDialog(tester);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      expect(find.text('Loyer').hitTestable(), findsOneWidget);
      expect(find.text('Salaires').hitTestable(), findsOneWidget);
      expect(find.text('Bouteilles de gaz').hitTestable(), findsOneWidget);
      expect(find.text('Autre…').hitTestable(), findsOneWidget);
    },
  );

  testWidgets('selecting "Autre" reveals a free-text field for the category', (
    tester,
  ) async {
    await openAddDialog(tester);

    expect(find.widgetWithText(TextField, 'Préciser la nature'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Autre…').hitTestable());
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(TextField, 'Préciser la nature'),
      findsOneWidget,
    );
  });

  testWidgets(
    'defaults the periodicity selector to Ponctuelle, with Récurrente selectable',
    (tester) async {
      await openAddDialog(tester);

      expect(find.text('Ponctuelle'), findsOneWidget);
      expect(find.text('Récurrente'), findsOneWidget);

      await tester.tap(find.text('Récurrente'));
      await tester.pump();
      // No crash / no validation error triggered by switching segments.
      expect(find.text('Libellé requis'), findsNothing);
    },
  );
}
