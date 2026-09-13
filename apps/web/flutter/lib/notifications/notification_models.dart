class AppNotification {
  AppNotification({
    required this.id,
    this.userId,
    required this.title,
    this.body,
    this.readAt,
    required this.createdAt,
  });

  final String id;
  final String? userId;
  final String title;
  final String? body;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isBroadcast => userId == null;
  bool get isUnread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        userId: json['userId'] as String?,
        title: json['title'] as String,
        body: json['body'] as String?,
        readAt: json['readAt'] == null
            ? null
            : DateTime.parse(json['readAt'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
