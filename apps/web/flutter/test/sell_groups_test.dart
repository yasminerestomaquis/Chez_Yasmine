import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/catalog/models.dart';
import 'package:chez_yasmine/pos/sell_groups.dart';

/// Demande du 2026-10-15 : la saisie des recettes de boissons sans Gbêlê, de
/// Gbêlê et de plats s'accorde ou se refuse rôle par rôle (`pos.sell_*`).
Product product(String name, {Category? category}) => Product(
      id: name,
      name: name,
      status: 'active',
      stockQuantity: 10,
      salePrice: 500,
      category: category,
    );

final casier = Category(id: 'c1', name: 'Bières', hasCasePricing: true);
final gbele = Category(id: 'c2', name: 'Gbêlê', isBeverage: true);
final plats = Category(id: 'c3', name: 'Plats africains', hasVariablePricing: true);
final ordinaire = Category(id: 'c4', name: 'Divers');

void main() {
  group('sellPermissionOf', () {
    test('même découpage que les recettes de l’Accueil', () {
      expect(sellPermissionOf(product('Castel', category: casier)), sellBeveragesPermission);
      expect(sellPermissionOf(product('Gbêlê', category: gbele)), sellGbelePermission);
      expect(sellPermissionOf(product('Kedjenou', category: plats)), sellPlatsPermission);
    });

    test('catégorie ordinaire ou absente : aucune permission de groupe', () {
      expect(sellPermissionOf(product('Savon', category: ordinaire)), isNull);
      expect(sellPermissionOf(product('Sans catégorie')), isNull);
    });
  });

  group('sellableProducts', () {
    final all = [
      product('Castel', category: casier),
      product('Gbêlê', category: gbele),
      product('Kedjenou', category: plats),
      product('Savon', category: ordinaire),
    ];

    test('droits inconnus (hors ligne) : rien n’est masqué', () {
      expect(sellableProducts(all, null), hasLength(4));
    });

    test('un rôle qui ne peut pas saisir les plats ne les voit plus', () {
      final names = sellableProducts(all, {sellBeveragesPermission, sellGbelePermission}).map((p) => p.name);
      expect(names, ['Castel', 'Gbêlê', 'Savon']);
    });

    test('aucun groupe accordé : seuls les produits hors groupe restent', () {
      expect(sellableProducts(all, <String>{}).map((p) => p.name), ['Savon']);
    });
  });
}
