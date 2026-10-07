import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/catalog/models.dart';
import 'package:chez_yasmine/pos/pos_page.dart';

/// Demande du 2026-10-07 : un produit dont le « lot » ne contient qu'une unité
/// (Cody's Energy, « Lot (1) — 600 » / « Unité — 600 ») se vend directement à
/// l'unité, sans la question « Comment vendre ce produit ? ».
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  Product product({String? unit, double? unitSalePrice = 600}) => Product(
    id: 'p1',
    name: "Cody's Energy",
    status: 'active',
    stockQuantity: 24,
    salePrice: 600,
    unitSalePrice: unitSalePrice,
    unit: unit,
  );

  group('Product.isSoldAsSingleUnitOnly', () {
    test('lot d\'une seule unité avec prix à l\'unité → vendu à l\'unité uniquement', () {
      expect(product(unit: '1').isSoldAsSingleUnitOnly, isTrue);
      expect(product(unit: ' 1 ').isSoldAsSingleUnitOnly, isTrue);
    });

    test(
      'vrai lot (3) ou taille inconnue → le choix Lot/Unité reste proposé',
      () {
        expect(product(unit: '3').isSoldAsSingleUnitOnly, isFalse);
        expect(product(unit: '12').isSoldAsSingleUnitOnly, isFalse);
        expect(product(unit: null).isSoldAsSingleUnitOnly, isFalse);
        expect(product(unit: 'Bouteille').isSoldAsSingleUnitOnly, isFalse);
      },
    );

    test('sans prix à l\'unité, aucun choix n\'est jamais proposé', () {
      expect(
        product(unit: '1', unitSalePrice: null).isSoldAsSingleUnitOnly,
        isFalse,
      );
    });
  });

  group('Caisse', () {
    http.Response json(Object body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
    );

    MockClient catalog(String unit) => MockClient((request) async {
      if (request.url.path.endsWith('/categories')) {
        return json([
          {'id': 'c1', 'name': 'Boissons'},
        ]);
      }
      if (request.url.path.endsWith('/products')) {
        return json([
          {
            'id': 'p1',
            'name': "Cody's Energy",
            'categoryId': 'c1',
            'unit': unit,
            'salePrice': 600,
            'unitSalePrice': 600,
            'stockQuantity': 24,
            'status': 'active',
          },
        ]);
      }
      return json({});
    });

    Future<void> openAndTap(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PosPage(establishmentId: 'est-1', roleName: 'Caissier'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text("Cody's Energy"));
      await tester.pumpAndSettle();
    }

    testWidgets(
      '« Lot (1) » : le produit est ajouté directement, sans question',
      (tester) async {
        await http.runWithClient(() async {
          await openAndTap(tester);
          expect(find.text('Comment vendre ce produit ?'), findsNothing);
          expect(find.textContaining('Lot (1)'), findsNothing);
        }, () => catalog('1'));
      },
    );

    testWidgets('« Lot (3) » : la question Lot/Unité est toujours posée', (
      tester,
    ) async {
      await http.runWithClient(() async {
        await openAndTap(tester);
        expect(find.text('Comment vendre ce produit ?'), findsOneWidget);
        expect(find.textContaining('Lot (3)'), findsOneWidget);
        expect(find.textContaining('Unité'), findsOneWidget);
      }, () => catalog('3'));
    });
  });
}
