import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/cash/cash_page.dart';

void main() {
  Future<void> openClosingDialog(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CashPage(establishmentId: 'est-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
  }

  testWidgets('the closing dialog defaults to a "opened since" field and a counted-amount field', (tester) async {
    await openClosingDialog(tester);

    expect(find.text('Clôture de caisse'), findsOneWidget);
    expect(find.text('Ouverte depuis'), findsOneWidget);
    expect(find.text('Montant compté en caisse *'), findsOneWidget);
  });

  testWidgets('rejects an invalid counted amount', (tester) async {
    await openClosingDialog(tester);

    await tester.tap(find.text('Clôturer'));
    await tester.pump();

    expect(find.text('Montant invalide'), findsOneWidget);
  });

  testWidgets('accepts zero as a valid counted amount', (tester) async {
    await openClosingDialog(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Montant compté en caisse *'), '0');
    await tester.tap(find.text('Clôturer'));
    await tester.pump();

    expect(find.text('Montant invalide'), findsNothing);
  });
}
