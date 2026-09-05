class Loss {
  Loss({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    this.reason,
    required this.estimatedValue,
    required this.createdAt,
  });

  final String id;
  final String productId;
  final String productName;
  final double quantity;
  final String? reason;
  final double estimatedValue;
  final DateTime createdAt;

  factory Loss.fromJson(Map<String, dynamic> json) => Loss(
        id: json['id'] as String,
        productId: json['productId'] as String,
        productName: json['productName'] as String,
        quantity: (json['quantity'] as num).toDouble(),
        reason: json['reason'] as String?,
        estimatedValue: (json['estimatedValue'] as num).toDouble(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
