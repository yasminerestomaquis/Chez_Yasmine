import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/api/api_client.dart';
import 'package:chez_yasmine/catalog/catalog_repository.dart';
import 'package:chez_yasmine/catalog/models.dart';
import 'package:chez_yasmine/catalog/product_form_page.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  final repository = CatalogRepository(ApiClient(), 'establishment-1');
  final categories = [Category(id: 'cat-1', name: 'Boissons')];

  // The form is a long ListView — a tall test viewport avoids relying on
  // scrolling to reach fields further down, since ListView only builds
  // what's visible.
  Future<void> pumpForm(WidgetTester tester, {Product? existing}) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: ProductFormPage(repository: repository, categories: categories, existing: existing)),
    );
  }

  testWidgets('shows the required fields and all four photo-picker options', (tester) async {
    await pumpForm(tester);

    expect(find.text('Nom *'), findsOneWidget);
    expect(find.text('Prix de vente (FCFA) *'), findsOneWidget);
    expect(find.text('Prendre une photo'), findsOneWidget);
    expect(find.text('Choisir dans la galerie'), findsOneWidget);
    expect(find.text('Importer un fichier'), findsOneWidget);
    expect(find.text('Image générique'), findsOneWidget);
    expect(find.text('Créer le produit'), findsOneWidget);
  });

  testWidgets('selecting the generic image shows a preview', (tester) async {
    await pumpForm(tester);

    expect(find.byType(Image), findsNothing);
    await tester.tap(find.text('Image générique'));
    await tester.pumpAndSettle();

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('validation blocks submission when the name is empty', (tester) async {
    await pumpForm(tester);

    await tester.enterText(find.widgetWithText(TextFormField, 'Prix de vente (FCFA) *'), '1000');
    await tester.tap(find.text('Créer le produit'));
    await tester.pump();

    expect(find.text('Requis'), findsOneWidget);
  });

  testWidgets('editing an existing product pre-fills its fields and shows "Enregistrer"', (tester) async {
    final product = Product(id: 'prod-1', name: 'Bière 65cl', salePrice: 1000, status: 'active', stockQuantity: 12);
    await pumpForm(tester, existing: product);

    expect(find.text('Modifier le produit'), findsOneWidget);
    expect(find.text('Bière 65cl'), findsOneWidget);
    expect(find.text('Enregistrer'), findsOneWidget);
    expect(find.text('Stock initial'), findsNothing);
  });
}
