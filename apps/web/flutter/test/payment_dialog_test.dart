import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/pos/payment_dialog.dart';

void main() {
  Future<PaymentOutcome?> openAndCapture(
    WidgetTester tester, {
    required double total,
  }) async {
    PaymentOutcome? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                result = await showPaymentDialog(context, total: total),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets(
    'the submit button is always enabled, even before any payment line is added '
    '(2026-09-13: no separate "Ajouter la ligne de paiement" step anymore)',
    (tester) async {
      await openAndCapture(tester, total: 5000);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Valider le paiement'),
      );
      expect(button.onPressed, isNotNull);
      expect(find.text('Ajouter la ligne de paiement'), findsNothing);
    },
  );

  testWidgets('a single click on Valider le paiement completes a full single-method payment '
      '(amount field is pre-filled with the total)', (tester) async {
    PaymentOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                outcome = await showPaymentDialog(context, total: 5000),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Valider le paiement'));
    await tester.pumpAndSettle();

    expect(outcome, isNotNull);
    expect(outcome!.lines, hasLength(1));
    expect(outcome!.lines.single.method, 'cash');
    expect(outcome!.lines.single.amount, 5000);
  });

  testWidgets(
    'splitting the payment across two methods: each click on Valider le paiement '
    'that leaves a balance keeps the dialog open for the next line',
    (tester) async {
      PaymentOutcome? outcome;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async =>
                  outcome = await showPaymentDialog(context, total: 5000),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // First line: cash 2000 (replace the pre-filled 5000), does not cover
      // the total — dialog stays open instead of closing.
      await tester.enterText(find.byType(TextField), '2000');
      await tester.tap(find.text('Valider le paiement'));
      await tester.pumpAndSettle();

      expect(outcome, isNull);
      expect(find.text('Espèces : 2 000 FCFA'), findsOneWidget);
      // Remaining 3000 should now be pre-filled for the second line.
      expect(find.text('3000'), findsOneWidget);

      // Switch method to Mobile Money and complete with the remaining 3000.
      await tester.tap(find.text('Espèces').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobile Money').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valider le paiement'));
      await tester.pumpAndSettle();

      expect(outcome, isNotNull);
      expect(outcome!.lines, hasLength(2));
      expect(outcome!.lines[0].method, 'cash');
      expect(outcome!.lines[0].amount, 2000);
      expect(outcome!.lines[1].method, 'mobile_money');
      expect(outcome!.lines[1].amount, 3000);
    },
  );

  testWidgets(
    'removing a payment line brings back the amount/method inputs and updates the remaining balance',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showPaymentDialog(context, total: 1000),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // A partial line (400 of 1000) keeps the dialog open.
      await tester.enterText(find.byType(TextField), '400');
      await tester.tap(find.text('Valider le paiement'));
      await tester.pumpAndSettle();
      expect(find.text('Espèces : 400 FCFA'), findsOneWidget);
      expect(find.text('Restant :'), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Espèces : 400 FCFA'), findsNothing);
      // Back to the full 1000 remaining: the amount/method row is shown
      // again rather than the "Restant" read-only text.
      expect(find.byType(TextField), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Valider le paiement'),
      );
      expect(button.onPressed, isNotNull);
    },
  );

  testWidgets(
    'only Espèces and Mobile Money are offered — Carte/Crédit removed (2026-09-10)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showPaymentDialog(context, total: 1000),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Espèces').last);
      await tester.pumpAndSettle();

      expect(find.text('Mobile Money').last, findsOneWidget);
      expect(find.text('Carte'), findsNothing);
      expect(find.text('Crédit'), findsNothing);
    },
  );
}
