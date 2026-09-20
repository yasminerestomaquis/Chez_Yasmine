class Loss {
  Loss({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    this.reason,
    required this.estimatedValue,
    this.createdByName,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final String productName;
  final double quantity;
  final String? reason;
  final double estimatedValue;

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
        createdByName: json['createdByName'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
