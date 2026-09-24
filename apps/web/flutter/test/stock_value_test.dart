import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/catalog/models.dart';
import 'package:chez_yasmine/stock/stock_value.dart';

Category _category({required String id, required String name, bool hasCasePricing = false, bool isBeverage = false}) =>
    Category(id: id, name: name, hasCasePricing: hasCasePricing, isBeverage: isBeverage);

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
  bool requiresPriceAtSale = false,
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
  requiresPriceAtSale: requiresPriceAtSale,
);

void main() {
  group('stockBottleCount (2026-09-22)', () {
    final bieres = _category(id: 'c1', name: 'Bières', hasCasePricing: true);
    final vins = _category(id: 'c2', name: 'Vins', hasCasePricing: true);
    final gbele = _category(id: 'c3', name: 'Gbêlê');
    final poulets = _category(id: 'c4', name: 'Poulets');

    test('sans sélection : additionne le stock des seules catégories à prix par casier', () {
      final products = [
        _product(id: 'beaufort', stockQuantity: 8, category: bieres),
        _product(id: 'vin100', stockQuantity: 5, category: vins),
        _product(id: 'gbele', stockQuantity: 3, category: gbele),
        _product(id: 'poulet', stockQuantity: 10, category: poulets),
      ];

      expect(stockBottleCount(products, {}), 13);
    });

    test('ignore un produit sans catégorie et une quantité négative/nulle', () {
      final products = [
        _product(id: 'beaufort', stockQuantity: 8, category: bieres),
        _product(id: 'sans-categorie', stockQuantity: 4),
        _product(id: 'rupture', stockQuantity: -2, category: bieres),
      ];

      expect(stockBottleCount(products, {}), 8);
    });

    test('vide sans produit de catégorie à prix par casier', () {
      expect(stockBottleCount([_product(id: 'gbele', stockQuantity: 3, category: gbele)], {}), 0);
    });

    test('suit la sélection du filtre Catégorie (2026-09-22)', () {
      final products = [
        _product(id: 'beaufort', stockQuantity: 8, category: bieres),
        _product(id: 'vin100', stockQuantity: 5, category: vins),
      ];

      expect(stockBottleCount(products, {'c1'}), 8);
    });

    test('une catégorie sélectionnée hors bouteilles donne 0, même si dautres bouteilles existent', () {
      final products = [
        _product(id: 'beaufort', stockQuantity: 8, category: bieres),
        _product(id: 'poulet', stockQuantity: 10, category: poulets),
      ];

      expect(stockBottleCount(products, {'c4'}), 0);
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

  group('hasReferencePricedSelection / stockReferenceLiters (2026-09-25)', () {
    final gbele = _category(id: 'c1', name: 'Gbêlê', isBeverage: true);
    final bieres = _category(id: 'c2', name: 'Bières', hasCasePricing: true);
    final gbeleProduct = _product(
      id: 'gbele',
      stockQuantity: 7,
      category: gbele,
      requiresPriceAtSale: true,
      referenceSalePrice: 3000,
      purchasePrice: 1100,
    );
    final beaufort = _product(id: 'beaufort', stockQuantity: 8, category: bieres);

    test('faux sans sélection', () {
      expect(hasReferencePricedSelection([gbeleProduct, beaufort], {}), isFalse);
    });

    test('vrai quand la catégorie Gbêlê est sélectionnée', () {
      expect(hasReferencePricedSelection([gbeleProduct, beaufort], {'c1'}), isTrue);
    });

    test('faux pour une sélection de catégories à prix par casier', () {
      expect(hasReferencePricedSelection([gbeleProduct, beaufort], {'c2'}), isFalse);
    });

    test('stockReferenceLiters ne compte que les produits à prix de référence variable de la sélection', () {
      expect(stockReferenceLiters([gbeleProduct, beaufort], {'c1'}), 7);
      expect(stockReferenceLiters([gbeleProduct, beaufort], {'c2'}), 0);
    });
  });
}
