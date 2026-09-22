import '../catalog/models.dart';

/// Prix d'achat d'une unité de stock : `purchasePrice` s'il est saisi, sinon
/// prix d'achat par casier ÷ bouteilles par casier (catégories à prix par
/// casier) ; 0 si rien n'est renseigné.
double stockUnitPurchaseCost(Product product) {
  if (product.purchasePrice != null) return product.purchasePrice!;
  if (product.purchasePricePerCase != null && product.bottlesPerCase != null && product.bottlesPerCase! > 0) {
    return product.purchasePricePerCase! / product.bottlesPerCase!;
  }
  return 0;
}

/// Prix de vente d'une unité de stock (la bouteille, le litre…) : le prix à
/// l'unité quand le produit se vend aussi par lot (`unitSalePrice`, le stock
/// étant compté en unités), sinon `salePrice`, sinon le prix de référence
/// (produit dont le prix se saisit à chaque vente, ex. Gbêlê), sinon 0.
double stockUnitSalePrice(Product product) =>
    product.unitSalePrice ?? product.salePrice ?? product.referenceSalePrice ?? 0;

/// Valeur du stock aux prix d'achat et de vente pour les catégories choisies
/// (aucune sélection = tout le catalogue) — demande utilisateur du 2026-09-22.
({double purchase, double sale}) stockValueTotals(List<Product> products, Set<String> selectedCategoryIds) {
  var purchase = 0.0;
  var sale = 0.0;
  for (final product in products) {
    if (selectedCategoryIds.isNotEmpty && !selectedCategoryIds.contains(product.categoryId)) continue;
    final quantity = product.stockQuantity;
    if (quantity <= 0) continue;
    purchase += quantity * stockUnitPurchaseCost(product);
    sale += quantity * stockUnitSalePrice(product);
  }
  return (purchase: purchase, sale: sale);
}
