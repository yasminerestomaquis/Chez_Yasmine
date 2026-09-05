class CashClosing {
  CashClosing({
    required this.id,
    required this.openedAt,
    required this.closedAt,
    required this.expectedAmount,
    required this.countedAmount,
    required this.difference,
  });

  final String id;
  final DateTime openedAt;
  final DateTime closedAt;
  final double expectedAmount;
  final double countedAmount;
  final double difference;

  factory CashClosing.fromJson(Map<String, dynamic> json) => CashClosing(
        id: json['id'] as String,
        openedAt: DateTime.parse(json['openedAt'] as String),
        closedAt: DateTime.parse(json['closedAt'] as String),
        expectedAmount: (json['expectedAmount'] as num).toDouble(),
        countedAmount: (json['countedAmount'] as num).toDouble(),
        difference: (json['difference'] as num).toDouble(),
      );
}
