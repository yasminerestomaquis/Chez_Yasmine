import '../catalog/models.dart';
import '../pos/pos_models.dart';

/// Quantité de stock que le serveur retirera pour une ligne vendue — même
/// règle que `SalesService.create` : un produit à prix fixe consomme la
/// quantité demandée ; un produit à prix de référence variable (ex. Gbêlê) est
/// saisi par MONTANT payé et le serveur en déduit la quantité
/// (`resolveReferencePriceLine`, arrondie à 2 décimales).
double stockUsedByLine(Product product, {required double quantity, double? manualAmount}) {
  final reference = product.referenceSalePrice;
  if (product.salePrice == null && reference != null && reference > 0 && manualAmount != null) {
    return (manualAmount / reference * 100).round() / 100;
  }
  return quantity;
}

/// Stock total à retirer par produit (un produit peut occuper plusieurs
/// lignes du panier, par exemple à des prix différents).
Map<String, double> stockNeeded(Iterable<({String productId, double quantity})> lines) {
  final needed = <String, double>{};
  for (final line in lines) {
    needed[line.productId] = (needed[line.productId] ?? 0) + line.quantity;
  }
  return needed;
}

/// Noms des produits dont le stock connu de l'appareil ne couvre pas la vente.
/// Simple avertissement : la vente a déjà eu lieu au comptoir, c'est le serveur
/// qui tranche à la synchronisation.
List<String> stockShortages(Map<String, double> needed, Map<String, Product> products) {
  return [
    for (final entry in needed.entries)
      if (products[entry.key] != null && products[entry.key]!.stockQuantity < entry.value) products[entry.key]!.name,
  ];
}

class ProvisionalLine {
  ProvisionalLine({required this.productId, required this.name, required this.quantity, required this.unitPrice});

  final String productId;
  final String name;
  final double quantity;
  final double unitPrice;
}

/// Reçu établi sur l'appareil pour une vente enregistrée hors ligne : mêmes
/// champs qu'une vente renvoyée par le serveur, pour réutiliser `ReceiptPage`.
/// `id` est l'identifiant d'idempotence de la vente — le futur identifiant
/// serveur (voir docs/api/sync.md).
SaleResult provisionalSale({
  required String id,
  required DateTime createdAt,
  required List<ProvisionalLine> lines,
  required List<({String method, double amount})> payments,
  int? orderNumber,
  int? marketNumber,
}) {
  final subtotal = lines.fold<double>(0, (sum, l) => sum + l.quantity * l.unitPrice);
  return SaleResult(
    id: id,
    subtotal: subtotal,
    discount: 0,
    total: subtotal,
    createdAt: createdAt,
    items: [
      for (var i = 0; i < lines.length; i++)
        SaleItemResult(
          id: '$id-$i',
          productId: lines[i].productId,
          name: lines[i].name,
          quantity: lines[i].quantity,
          unitPrice: lines[i].unitPrice,
        ),
    ],
    payments: [
      for (var i = 0; i < payments.length; i++)
        PaymentResult(id: '$id-p$i', method: payments[i].method, amount: payments[i].amount),
    ],
    orderNumber: orderNumber,
    marketNumber: marketNumber,
  );
}
