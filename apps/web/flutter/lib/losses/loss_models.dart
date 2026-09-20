class Loss {
  Loss({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    this.reason,
    required this.estimatedValue,
    this.unitSalePrice = 0,
    this.sellAsUnit = false,
    this.hasUnitPrice = false,
    this.orderNumber,
    this.createdByName,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final String productName;
  final double quantity;
  final String? reason;
  /// Valeur de la perte : quantité × prix de vente du produit (prix de vente
  /// de référence si le prix se saisit à chaque vente, décision du 2026-09-20).
  final double estimatedValue;
  final double unitSalePrice;

  /// Perte valorisée au prix à l'unité plutôt qu'au tarif du lot.
  final bool sellAsUnit;

  /// Le produit se vend par lot ET à l'unité (le choix Lot/Unité s'applique).
  final bool hasUnitPrice;

  /// N° de la commande du lot concerné (produits à prix par casier) ; nul avant cette évolution.
  final int? orderNumber;

  /// Nom complet de l'auteur (`UserProfile.fullName`) ; nul si inconnu.
  final String? createdByName;
  final DateTime createdAt;

  factory Loss.fromJson(Map<String, dynamic> json) => Loss(
        id: json['id'] as String,
        productId: json['productId'] as String,
        productName: json['productName'] as String,
        quantity: (json['quantity'] as num).toDouble(),
        reason: json['reason'] as String?,
        estimatedValue: (json['estimatedValue'] as num).toDouble(),
        unitSalePrice: (json['unitSalePrice'] as num?)?.toDouble() ?? 0,
        sellAsUnit: json['sellAsUnit'] as bool? ?? false,
        hasUnitPrice: json['hasUnitPrice'] as bool? ?? false,
        orderNumber: (json['orderNumber'] as num?)?.toInt(),
        createdByName: json['createdByName'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
