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

  group('lineItemsTotal (logique pure, sans réseau) — 2026-09-17', () {
    test('somme qté × prix unitaire des lignes fournies', () {
      final items = [
        SaleItemResult(id: 'i1', productId: 'p1', name: 'Chill', quantity: 1, unitPrice: 500),
        SaleItemResult(id: 'i2', productId: 'p2', name: 'Bock', quantity: 3, unitPrice: 600),
      ];

      expect(lineItemsTotal(items), 2300);
    });

    test('vaut 0 pour une liste vide', () {
      expect(lineItemsTotal(const []), 0);
    });
  });

  group('vente mixte : le sous-total par carte ne doit jamais utiliser sale.total (2026-09-17)', () {
    test('une vente mêlant plats et boissons a un sous-total par catégorie distinct de sale.total', () {
      final sale = _sale(
        id: 's1',
        items: [
          SaleItemResult(id: 'i1', productId: 'plat-1', name: 'Foutou Sauce', quantity: 1, unitPrice: 1000),
          SaleItemResult(id: 'i2', productId: 'biere-1', name: 'Chill', quantity: 1, unitPrice: 500),
          SaleItemResult(id: 'i3', productId: 'biere-2', name: 'Bock', quantity: 3, unitPrice: 600),
        ],
        payments: [PaymentResult(id: 'pay-1', method: 'mobile_money', amount: 3300)],
      );

      final boissons = matchingSalesWithTotal([sale], {'biere-1', 'biere-2'});
      final plats = matchingSalesWithTotal([sale], {'plat-1'});

      // Sous-total Boissons : 500 + 1800 = 2300, jamais les 3300 de sale.total.
      expect(lineItemsTotal(boissons.matches.single.items), 2300);
      expect(boissons.total, 2300);
      // Sous-total Plats : 1000 seul, jamais les 3300 de sale.total.
      expect(lineItemsTotal(plats.matches.single.items), 1000);
      expect(plats.total, 1000);
      // La vente réelle (sale.total, servant à "Rembourser cette vente" et
      // affiché comme tel en cas de vente mixte) reste bien 3300 dans les deux vues.
      expect(boissons.matches.single.sale.total, 3300);
      expect(plats.matches.single.sale.total, 3300);
      // Signature d'une vente mixte utilisée par la carte pour afficher la
      // précision "vente mixte" et le vrai montant du paiement : le nombre
      // de lignes affichées est inférieur au nombre total de lignes de la vente.
      expect(boissons.matches.single.items.length, isNot(sale.items.length));
      expect(plats.matches.single.items.length, isNot(sale.items.length));
    });

    test('une vente "pure" (une seule catégorie) a un sous-total identique à sale.total', () {
      final sale = _sale(
        id: 's1',
        items: [SaleItemResult(id: 'i1', productId: 'eau-1', name: 'Eau Bassam', quantity: 1, unitPrice: 100)],
      );

      final result = matchingSalesWithTotal([sale], {'eau-1'});

      expect(lineItemsTotal(result.matches.single.items), 100);
      expect(result.matches.single.sale.total, 100);
      expect(result.matches.single.items.length, sale.items.length);
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
