import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/catalog/models.dart';

void main() {
  group('Category.fromJson', () {
    test('defaults isBeverage to false when absent', () {
      final category = Category.fromJson({'id': 'c1', 'name': 'Bières', 'hasCasePricing': true});

      expect(category.isBeverage, isFalse);
    });

    test('reads isBeverage when present', () {
      final category = Category.fromJson({'id': 'c2', 'name': 'Gbêlê', 'isBeverage': true});

      expect(category.isBeverage, isTrue);
    });
  });

  group('Product.isBoissonsGroup (décision utilisateur du 2026-09-17 — Gbêlê compte comme Boissons)', () {
    test('vrai pour une catégorie à prix par casier (ex. Bières)', () {
      final product = Product(
        id: 'p1',
        name: 'Heineken',
        status: 'active',
        stockQuantity: 10,
        category: Category(id: 'c1', name: 'Bières', hasCasePricing: true),
      );

      expect(product.isBoissonsGroup, isTrue);
    });

    test('vrai pour une catégorie isBeverage sans prix par casier (ex. Gbêlê)', () {
      final product = Product(
        id: 'p2',
        name: 'Gbêlê',
        status: 'active',
        stockQuantity: 1.5,
        category: Category(id: 'c2', name: 'Gbêlê', isBeverage: true),
      );

      expect(product.isBoissonsGroup, isTrue);
      expect(product.hasCasePricing, isFalse);
    });

    test('faux pour une catégorie à prix variable (ex. Poulets)', () {
      final product = Product(
        id: 'p3',
        name: 'Poulet braisé',
        status: 'active',
        stockQuantity: 5,
        category: Category(id: 'c3', name: 'Poulets', hasVariablePricing: true),
      );

      expect(product.isBoissonsGroup, isFalse);
    });

    test('faux sans catégorie', () {
      final product = Product(id: 'p4', name: 'Sans catégorie', status: 'active', stockQuantity: 0);

      expect(product.isBoissonsGroup, isFalse);
    });
  });

  group('Product.isReferencePriced (décision utilisateur du 2026-09-24 — Gbêlê)', () {
    test('vrai pour Gbêlê : catégorie fixe, requiresPriceAtSale et referenceSalePrice renseignés', () {
      final product = Product(
        id: 'p1',
        name: 'Gbêlê',
        status: 'active',
        stockQuantity: 39.5,
        category: Category(id: 'c1', name: 'Gbêlê', isBeverage: true),
        requiresPriceAtSale: true,
        referenceSalePrice: 3000,
      );

      expect(product.isReferencePriced, isTrue);
    });

    test('faux sans referenceSalePrice, même avec requiresPriceAtSale', () {
      final product = Product(
        id: 'p2',
        name: 'X',
        status: 'active',
        stockQuantity: 1,
        category: Category(id: 'c1', name: 'Gbêlê', isBeverage: true),
        requiresPriceAtSale: true,
      );

      expect(product.isReferencePriced, isFalse);
    });

    test('faux pour une catégorie à prix par casier, même avec requiresPriceAtSale/referenceSalePrice', () {
      final product = Product(
        id: 'p3',
        name: 'X',
        status: 'active',
        stockQuantity: 1,
        category: Category(id: 'c1', name: 'Bières', hasCasePricing: true),
        requiresPriceAtSale: true,
        referenceSalePrice: 3000,
      );

      expect(product.isReferencePriced, isFalse);
    });

    test('faux pour Poulets (prix variable classique, sans referenceSalePrice)', () {
      final product = Product(
        id: 'p4',
        name: 'Poulet braisé',
        status: 'active',
        stockQuantity: 5,
        category: Category(id: 'c3', name: 'Poulets', hasVariablePricing: true),
      );

      expect(product.isReferencePriced, isFalse);
    });
  });
}
