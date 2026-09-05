/// Mirrors apps/api/nestjs/src/sync/dto/sync-batch.dto.ts — entityType is
/// either 'sale' or 'stock_movement' (see prompt maître §25-27).
class PendingOperation {
  PendingOperation({
    required this.id,
    required this.entityType,
    required this.deviceId,
    required this.payload,
    required this.createdAt,
    this.attemptCount = 0,
    this.lastError,
  });

  final String id;
  final String entityType;
  final String deviceId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  int attemptCount;
  String? lastError;

  Map<String, dynamic> toJson() => {
        'id': id,
        'entityType': entityType,
        'deviceId': deviceId,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'attemptCount': attemptCount,
        'lastError': lastError,
      };

  factory PendingOperation.fromJson(Map<String, dynamic> json) => PendingOperation(
        id: json['id'] as String,
        entityType: json['entityType'] as String,
        deviceId: json['deviceId'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        createdAt: DateTime.parse(json['createdAt'] as String),
        attemptCount: json['attemptCount'] as int? ?? 0,
        lastError: json['lastError'] as String?,
      );
}
