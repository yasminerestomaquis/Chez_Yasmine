import '../catalog/models.dart';

/// Saisie des recettes par groupe (demande utilisateur du 2026-10-15) :
/// vendre en Caisse ou ajouter à une addition des boissons sans Gbêlê, du Gbêlê
/// ou des plats peut être accordé ou refusé rôle par rôle depuis « Gestion des
/// permissions ». Même découpage que le serveur
/// (`apps/api/nestjs/src/pos/sell-groups.ts`) et que les recettes de l'Accueil.
const sellBeveragesPermission = 'pos.sell_beverages';
const sellGbelePermission = 'pos.sell_gbele';
const sellPlatsPermission = 'pos.sell_plats';

/// Permission requise pour vendre [product], ou `null` s'il ne relève d'aucun
/// groupe (catégorie à prix fixe ordinaire, ou sans catégorie) : seul `pos.sell`
/// s'applique alors.
String? sellPermissionOf(Product product) {
  final category = product.category;
  if (category == null) return null;
  if (category.hasVariablePricing) return sellPlatsPermission;
  if (category.isBeverage && !category.hasCasePricing) return sellGbelePermission;
  if (category.hasCasePricing) return sellBeveragesPermission;
  return null;
}

/// Produits que le rôle a le droit de saisir. [allowed] `null` : droits
/// inconnus (lecture impossible, hors ligne) — rien n'est masqué, le serveur
/// refusera au besoin.
List<Product> sellableProducts(List<Product> products, Set<String>? allowed) {
  if (allowed == null) return products;
  return [
    for (final product in products)
      if (sellPermissionOf(product) == null || allowed.contains(sellPermissionOf(product))) product,
  ];
}
