import '../catalog/models.dart';

/// A line in the cart being built at the register — not yet a Sale.
class CartLine {
  CartLine({required this.product, required this.quantity, this.manualUnitPrice});

  final Product product;
  int quantity;
  /// Saisi par le caissier pour un produit à prix variable (`product.salePrice`
  /// nul, ex. Poulets/Poissons/Plats africains) — voir `PosPage._addToCart`.
  final double? manualUnitPrice;

  double get unitPrice => manualUnitPrice ?? product.salePrice ?? 0;
  double get lineTotal => unitPrice * quantity;
}

class SaleItemResult {
  SaleItemResult({required this.name, required this.quantity, required this.unitPrice});

  final String name;
  final double quantity;
  final double unitPrice;

  factory SaleItemResult.fromJson(Map<String, dynamic> json) => SaleItemResult(
        name: json['name'] as String,
        quantity: (json['quantity'] as num).toDouble(),
        unitPrice: (json['unitPrice'] as num).toDouble(),
      );
}

class PaymentResult {
  PaymentResult({required this.method, required this.amount});

  final String method;
  final double amount;

  factory PaymentResult.fromJson(Map<String, dynamic> json) =>
      PaymentResult(method: json['method'] as String, amount: (json['amount'] as num).toDouble());
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
  });

  final String id;
  final double subtotal;
  final double discount;
  final double total;
  final DateTime createdAt;
  final List<SaleItemResult> items;
  final List<PaymentResult> payments;
  final DateTime? voidedAt;

  factory SaleResult.fromJson(Map<String, dynamic> json) => SaleResult(
        id: json['id'] as String,
        subtotal: (json['subtotal'] as num).toDouble(),
        discount: (json['discount'] as num).toDouble(),
        total: (json['total'] as num).toDouble(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        items: (json['items'] as List<dynamic>).map((e) => SaleItemResult.fromJson(e as Map<String, dynamic>)).toList(),
        payments: (json['payments'] as List<dynamic>).map((e) => PaymentResult.fromJson(e as Map<String, dynamic>)).toList(),
        voidedAt: json['voidedAt'] != null ? DateTime.parse(json['voidedAt'] as String) : null,
      );
}

const paymentMethodLabels = {
  'cash': 'Espèces',
  'mobile_money': 'Mobile Money',
  'card': 'Carte',
  'credit': 'Crédit',
};
