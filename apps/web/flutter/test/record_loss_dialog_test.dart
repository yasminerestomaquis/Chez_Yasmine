import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/api/api_client.dart';
import 'package:chez_yasmine/catalog/catalog_repository.dart';
import 'package:chez_yasmine/losses/losses_repository.dart';
import 'package:chez_yasmine/losses/record_loss_dialog.dart';

void main() {
  final lossesRepository = LossesRepository(ApiClient(), 'est-1');
  final catalogRepository = CatalogRepository(ApiClient(), 'est-1');

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () =>
              showRecordLossDialog(context, repository: lossesRepository, catalogRepository: catalogRepository),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows an inline error when the product list fails to load (no network in tests)', (tester) async {
    await openDialog(tester);
    expect(find.text('Impossible de charger la liste des produits.'), findsOneWidget);
  });

  testWidgets('refuses to submit without a product selected, checked before form validation', (tester) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextFormField).last, '5');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(find.text('Choisissez un produit'), findsOneWidget);
  });

  testWidgets('has a required-quantity field and an optional reason field', (tester) async {
    await openDialog(tester);

    expect(find.text('Quantité perdue *'), findsOneWidget);
    expect(find.text('Motif (optionnel)'), findsOneWidget);
  });
}
