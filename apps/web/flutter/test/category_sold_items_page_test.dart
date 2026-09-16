import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/pos/category_sold_items_page.dart';
import 'package:chez_yasmine/pos/pos_models.dart';

SaleResult _sale({
  required String id,
  required List<SaleItemResult> items,
  List<PaymentResult> payments = const [],
  DateTime? voidedAt,
}) => SaleResult(
  id: id,
  subtotal: 0,
  discount: 0,
  total: items.fold<double>(0, (sum, i) => sum + i.quantity * i.unitPrice),
  createdAt: DateTime(2026, 9, 15, 12),
  items: items,
  payments: payments,
  voidedAt: voidedAt,
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  group('canRefundSale (logique pure, sans réseau) — 2026-09-16', () {
    test('le Serveur ne peut pas rembourser (pos.correct sans pos.refund)', () {
      expect(canRefundSale('Serveur'), isFalse);
    });

    test('les rôles portant pos.refund le peuvent', () {
      for (final role in ['Super Administrateur', 'Administrateur', 'Propriétaire', 'Gérant', 'Caissier']) {
        expect(canRefundSale(role), isTrue, reason: role);
      }
    });

    test('un rôle inconnu ne peut pas rembourser', () {
      expect(canRefundSale('Comptable'), isFalse);
      expect(canRefundSale('Magasinier'), isFalse);
    });
  });

  group('matchingSalesWithTotal (logique pure, sans réseau)', () {
    test('somme uniquement les lignes dont le produit est dans matchingProductIds', () {
      final sales = [
        _sale(
          id: 's1',
          items: [
            SaleItemResult(id: 'i1', productId: 'plat-1', name: 'Poulet braisé', quantity: 2, unitPrice: 1500),
            SaleItemResult(id: 'i2', productId: 'biere-1', name: 'Heineken 33', quantity: 1, unitPrice: 2000),
          ],
        ),
        _sale(
          id: 's2',
          items: [
            SaleItemResult(id: 'i3', productId: 'plat-1', name: 'Poulet braisé', quantity: 1, unitPrice: 1500),
          ],
        ),
      ];

      final result = matchingSalesWithTotal(sales, {'plat-1'});

      expect(result.total, 4500); // (2*1500) + (1*1500), la Heineken 33 exclue
      expect(result.matches, hasLength(2));
      expect(result.matches[0].items, hasLength(1)); // seule la ligne "plat-1" de s1, pas la Heineken 33
      expect(result.matches[0].items.single.productId, 'plat-1');
    });

    test('exclut une vente remboursée (voidedAt non nul)', () {
      final sales = [
        _sale(
          id: 's1',
          items: [SaleItemResult(id: 'i1', productId: 'plat-1', name: 'Poulet braisé', quantity: 1, unitPrice: 1500)],
          voidedAt: DateTime(2026, 9, 15, 13),
        ),
      ];

      final result = matchingSalesWithTotal(sales, {'plat-1'});

      expect(result.matches, isEmpty);
      expect(result.total, 0);
    });

    test('omet une vente qui ne contient aucune ligne correspondante', () {
      final sales = [
        _sale(
          id: 's1',
          items: [SaleItemResult(id: 'i1', productId: 'biere-1', name: 'Heineken 33', quantity: 1, unitPrice: 2000)],
        ),
      ];

      final result = matchingSalesWithTotal(sales, {'plat-1'});

      expect(result.matches, isEmpty);
      expect(result.total, 0);
    });
  });

  testWidgets(
    'Plats vendus shows an error state without crashing when no backend is reachable in test',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CategorySoldItemsPage.plats(establishmentId: 'est-1', roleName: 'Gérant'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Plats vendus'), findsOneWidget);
      // Pas de backend en test : le chargement échoue, le corps affiche le
      // message d'erreur plutôt que le listing (voir docs/api/reports.md).
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'Boissons vendues shows an error state without crashing when no backend is reachable in test',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CategorySoldItemsPage.boissons(establishmentId: 'est-1', roleName: 'Gérant'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Boissons vendues'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}
