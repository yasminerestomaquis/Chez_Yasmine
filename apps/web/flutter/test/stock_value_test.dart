import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/catalog/models.dart';
import 'package:chez_yasmine/stock/stock_value.dart';

Category _category({required String id, required String name, bool hasCasePricing = false}) =>
    Category(id: id, name: name, hasCasePricing: hasCasePricing);

Product _product({
  required String id,
  required double stockQuantity,
  Category? category,
  double? purchasePrice,
  double? salePrice,
  double? unitSalePrice,
  double? referenceSalePrice,
  double? purchasePricePerCase,
  int? bottlesPerCase,
}) => Product(
  id: id,
  name: id,
  status: 'active',
  stockQuantity: stockQuantity,
  categoryId: category?.id,
  category: category,
  purchasePrice: purchasePrice,
  salePrice: salePrice,
  unitSalePrice: unitSalePrice,
  referenceSalePrice: referenceSalePrice,
  purchasePricePerCase: purchasePricePerCase,
  bottlesPerCase: bottlesPerCase,
);

void main() {
  group('stockBottleCount (2026-09-22)', () {
    final bieres = _category(id: 'c1', name: 'Bières', hasCasePricing: true);
    final vins = _category(id: 'c2', name: 'Vins', hasCasePricing: true);
    final gbele = _category(id: 'c3', name: 'Gbêlê');
    final poulets = _category(id: 'c4', name: 'Poulets');

    test('additionne le stock des seules catégories à prix par casier', () {
      final products = [
        _product(id: 'beaufort', stockQuantity: 8, category: bieres),
        _product(id: 'vin100', stockQuantity: 5, category: vins),
        _product(id: 'gbele', stockQuantity: 3, category: gbele),
        _product(id: 'poulet', stockQuantity: 10, category: poulets),
      ];

      expect(stockBottleCount(products), 13);
    });

    test('ignore un produit sans catégorie et une quantité négative/nulle', () {
      final products = [
        _product(id: 'beaufort', stockQuantity: 8, category: bieres),
        _product(id: 'sans-categorie', stockQuantity: 4),
        _product(id: 'rupture', stockQuantity: -2, category: bieres),
      ];

      expect(stockBottleCount(products), 8);
    });

    test('vide sans produit de catégorie à prix par casier', () {
      expect(stockBottleCount([_product(id: 'gbele', stockQuantity: 3, category: gbele)]), 0);
    });
  });

  group('stockValueTotals (existant, non-régression)', () {
    final bieres = _category(id: 'c1', name: 'Bières', hasCasePricing: true);

    test('valorise au prix d’achat par casier et au prix de vente', () {
      final products = [
        _product(id: 'beaufort', stockQuantity: 2, category: bieres, purchasePricePerCase: 5400, bottlesPerCase: 12, salePrice: 700),
      ];

      final totals = stockValueTotals(products, {});

      expect(totals.purchase, closeTo(2 * (5400 / 12), 0.001));
      expect(totals.sale, 1400);
    });
  });
}
