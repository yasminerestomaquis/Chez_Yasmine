import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/pos/payment_dialog.dart';

void main() {
  Future<List<PaymentLine>?> openAndCapture(WidgetTester tester, {required double total}) async {
    List<PaymentLine>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async => result = await showPaymentDialog(context, total: total),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('the submit button is disabled until at least one payment line is added', (tester) async {
    await openAndCapture(tester, total: 5000);

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Valider le paiement'));
    expect(button.onPressed, isNull, reason: 'the amount field being pre-filled does not itself add a payment line');
  });

  testWidgets('splitting the payment across two methods sums correctly and then enables submission', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showPaymentDialog(context, total: 5000),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // First line: cash 2000 (replace the pre-filled 5000).
    await tester.enterText(find.byType(TextField), '2000');
    await tester.tap(find.text('Ajouter la ligne de paiement'));
    await tester.pumpAndSettle();

    expect(find.text('Espèces : 2000 FCFA'), findsOneWidget);
    // Remaining 3000 should now be pre-filled for the second line.
    expect(find.text('3000'), findsOneWidget);

    // Switch method to Mobile Money and add the remaining 3000.
    await tester.tap(find.text('Espèces').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mobile Money').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter la ligne de paiement'));
    await tester.pumpAndSettle();

    expect(find.text('Mobile Money : 3000 FCFA'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Valider le paiement'));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('removing a payment line updates the remaining balance', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showPaymentDialog(context, total: 1000),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ajouter la ligne de paiement'));
    await tester.pumpAndSettle();
    expect(find.text('Espèces : 1000 FCFA'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Espèces : 1000 FCFA'), findsNothing);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Valider le paiement'));
    expect(button.onPressed, isNull);
  });
}
