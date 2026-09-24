import '../catalog/models.dart';

/// A line in the cart being built at the register — not yet a Sale.
class CartLine {
  CartLine({
    required this.product,
    required this.quantity,
    this.manualUnitPrice,
    this.sellAsUnit = false,
  });

  final Product product;
  int quantity;

  /// Saisi par le caissier pour un produit à prix variable (`product.salePrice`
  /// nul) — voir `PosPage._addToCart`. Pour un produit à prix fixe "classique"
  /// (Poulets/Poissons/Plats africains) : le prix de vente lui-même. Pour un
  /// produit à prix de RÉFÉRENCE variable (`product.referenceSalePrice` non
  /// nul, ex. Gbêlê) : le MONTANT payé — envoyé au serveur comme `amountPaid`
  /// plutôt que `unitPrice` (voir `_checkout`), qui en déduit la quantité.
  final double? manualUnitPrice;

  /// Vente à l'unité plutôt qu'au tarif normal (ex. Heineken 33/Despé 33,
  /// vendues par lot de 3 à 2 000 FCFA, aussi disponibles à l'unité à 700
  /// FCFA — `product.unitSalePrice`) — voir `PosPage._addToCart`. Le serveur
  /// reste seul juge du prix réel : seul ce choix est transmis, jamais un
  /// montant (`CreateSaleDto.items[].sellAsUnit`).
  final bool sellAsUnit;

  double get unitPrice =>
      manualUnitPrice ??
      (sellAsUnit ? product.unitSalePrice : null) ??
      product.salePrice ??
      0;
  double get lineTotal => unitPrice * quantity;
}

class SaleItemResult {
  SaleItemResult({
    required this.id,
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });

  final String id;
  final String productId;
  final String name;
  final double quantity;
  final double unitPrice;

  factory SaleItemResult.fromJson(Map<String, dynamic> json) => SaleItemResult(
    id: json['id'] as String,
    productId: json['productId'] as String,
    name: json['name'] as String,
    quantity: (json['quantity'] as num).toDouble(),
    unitPrice: (json['unitPrice'] as num).toDouble(),
  );
}

class PaymentResult {
  PaymentResult({required this.id, required this.method, required this.amount});

  final String id;
  final String method;
  final double amount;

  factory PaymentResult.fromJson(Map<String, dynamic> json) => PaymentResult(
    id: json['id'] as String,
    method: json['method'] as String,
    amount: (json['amount'] as num).toDouble(),
  );
}

class SaleResult {
  SaleResult({
    required this.id,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.createdAt,
    required this.items,
    required this.payments,
    this.voidedAt,
    this.orderNumber,
    this.marketNumber,
  });

  final String id;
  final double subtotal;
  final double discount;
  final double total;
  final DateTime createdAt;
  final List<SaleItemResult> items;
  final List<PaymentResult> payments;
  final DateTime? voidedAt;

  /// Bières/Vins/Sucreries -> N° de la commande d'achat correspondante,
  /// saisi en caisse (voir `docs/api/pos.md`) — nul si non renseigné.
  final int? orderNumber;

  /// Poulets/Poissons/Plats africains -> N° de marché correspondant, même
  /// principe qu'`orderNumber` — nul si non renseigné.
  final int? marketNumber;

  factory SaleResult.fromJson(Map<String, dynamic> json) => SaleResult(
    id: json['id'] as String,
    subtotal: (json['subtotal'] as num).toDouble(),
    discount: (json['discount'] as num).toDouble(),
    total: (json['total'] as num).toDouble(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    items: (json['items'] as List<dynamic>)
        .map((e) => SaleItemResult.fromJson(e as Map<String, dynamic>))
        .toList(),
    payments: (json['payments'] as List<dynamic>)
        .map((e) => PaymentResult.fromJson(e as Map<String, dynamic>))
        .toList(),
    voidedAt: json['voidedAt'] != null
        ? DateTime.parse(json['voidedAt'] as String)
        : null,
    orderNumber: (json['orderNumber'] as num?)?.toInt(),
    marketNumber: (json['marketNumber'] as num?)?.toInt(),
  );
}

const paymentMethodLabels = {
  'cash': 'Espèces',
  'mobile_money': 'Mobile Money',
  'card': 'Carte',
  'credit': 'Crédit',
};
