import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/api/api_client.dart';
import 'package:chez_yasmine/stock/stock_movement_dialog.dart';
import 'package:chez_yasmine/stock/stock_repository.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  final repository = StockRepository(ApiClient(), 'establishment-1');

  Future<void> openDialog(WidgetTester tester, {bool hasVariablePricing = false}) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showStockMovementDialog(
            context,
            repository: repository,
            productId: 'prod-1',
            productName: 'Bière 65cl',
            hasVariablePricing: hasVariablePricing,
          ),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('defaults to "Entrée" and labels the field "Quantité *"', (tester) async {
    await openDialog(tester);

    expect(find.text('Mouvement de stock — Bière 65cl'), findsOneWidget);
    expect(find.text('Entrée'), findsOneWidget);
    expect(find.text('Quantité *'), findsOneWidget);
  });

  testWidgets('relabels the field for an adjustment', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Entrée'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correction').last);
    await tester.pumpAndSettle();

    expect(find.text('Nouvelle quantité totale *'), findsOneWidget);
  });

  testWidgets('blocks submission when the quantity is empty or invalid', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(find.text('Quantité invalide'), findsOneWidget);
  });

  testWidgets('does not show the market number field for a category without variable pricing', (tester) async {
    await openDialog(tester);

    expect(find.text('N° de marché *'), findsNothing);
  });

  testWidgets('requires a market number for an "in" entry on a variable-pricing category', (tester) async {
    await openDialog(tester, hasVariablePricing: true);

    expect(find.text('N° de marché *'), findsOneWidget);

    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(find.text('N° de marché invalide'), findsOneWidget);
  });

  testWidgets('hides the market number field once switched away from "in"', (tester) async {
    await openDialog(tester, hasVariablePricing: true);

    expect(find.text('N° de marché *'), findsOneWidget);

    await tester.tap(find.text('Entrée'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Correction').last);
    await tester.pumpAndSettle();

    expect(find.text('N° de marché *'), findsNothing);
  });
}
