import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/api/api_client.dart';
import 'package:chez_yasmine/catalog/catalog_repository.dart';
import 'package:chez_yasmine/catalog/models.dart';
import 'package:chez_yasmine/pos/product_grid.dart';
import 'package:chez_yasmine/theme/app_theme.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  final repository = CatalogRepository(ApiClient(), 'est-1');

  Future<void> pumpTile(WidgetTester tester, {required double stockQuantity}) async {
    final product = Product(id: 'p1', name: 'Celeste', salePrice: 500, status: 'active', stockQuantity: stockQuantity);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosProductTile(product: product, repository: repository, quantityInCart: 0, onTap: () {}),
        ),
      ),
    );
  }

  // Rupture de stock (2026-09-16, demande utilisateur) : contour rouge sur la
  // vignette pour repérer visuellement un produit épuisé, en Caisse comme
  // dans l'écran Addition (les deux réutilisent PosProductTile).
  group('contour rouge en rupture de stock', () {
    testWidgets('aucun contour rouge quand le stock est positif', (tester) async {
      await pumpTile(tester, stockQuantity: 5);

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.shape, isNull);
    });

    testWidgets('contour rouge quand le stock est à zéro', (tester) async {
      await pumpTile(tester, stockQuantity: 0);

      final card = tester.widget<Card>(find.byType(Card));
      final shape = card.shape as RoundedRectangleBorder;
      expect(shape.side.color, AppColors.alert);
    });

    testWidgets('contour rouge aussi pour un stock négatif', (tester) async {
      await pumpTile(tester, stockQuantity: -1);

      final card = tester.widget<Card>(find.byType(Card));
      final shape = card.shape as RoundedRectangleBorder;
      expect(shape.side.color, AppColors.alert);
    });
  });
}
