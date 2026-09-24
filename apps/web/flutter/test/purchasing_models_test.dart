import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/purchasing/purchasing_models.dart';

PurchaseItem _caseItem({double casesOrdered = 2}) => PurchaseItem(
      productId: 'p1',
      productName: 'Beaufort 50',
      casesOrdered: casesOrdered,
      bottlesPerCase: 12,
      purchasePricePerCase: 5400,
    );

PurchaseItem _literItem({double litersOrdered = 25}) => PurchaseItem(
      productId: 'p2',
      productName: 'Gbêlê',
      casesOrdered: litersOrdered,
      bottlesPerCase: 1,
      purchasePricePerCase: 1100,
    );

Purchase _purchase(List<PurchaseItem> items) => Purchase(
      id: 'pu1',
      orderNumber: 1,
      orderDate: DateTime(2026, 9, 24),
      status: 'received',
      total: items.fold(0, (sum, i) => sum + i.lineTotal),
      items: items,
    );

void main() {
  group('PurchaseItem.isLiters (2026-09-24 — Gbêlê commandé au litre)', () {
    test('faux pour une ligne au casier (bottlesPerCase > 1)', () {
      expect(_caseItem().isLiters, isFalse);
    });

    test('vrai pour une ligne au litre (bottlesPerCase == 1)', () {
      expect(_literItem().isLiters, isTrue);
    });
  });

  group('Purchase.totalCases / totalLiters', () {
    test('les deux totaux restent séparés dans une commande mêlant casiers et litres', () {
      final purchase = _purchase([_caseItem(casesOrdered: 2), _literItem(litersOrdered: 25)]);

      expect(purchase.totalCases, 2);
      expect(purchase.totalLiters, 25);
    });

    test('totalLiters à 0 pour une commande sans ligne au litre', () {
      final purchase = _purchase([_caseItem()]);

      expect(purchase.totalLiters, 0);
    });
  });

  group('purchaseQuantitySummary', () {
    test('combine casier(s) et L quand la commande mélange les deux', () {
      final purchase = _purchase([_caseItem(casesOrdered: 2), _literItem(litersOrdered: 25)]);

      expect(purchaseQuantitySummary(purchase), '2 casier(s) + 25 L');
    });

    test('seulement L pour une commande 100% Gbêlê', () {
      final purchase = _purchase([_literItem(litersOrdered: 50)]);

      expect(purchaseQuantitySummary(purchase), '50 L');
    });

    test('seulement casier(s) pour une commande classique', () {
      final purchase = _purchase([_caseItem(casesOrdered: 3)]);

      expect(purchaseQuantitySummary(purchase), '3 casier(s)');
    });
  });
}
