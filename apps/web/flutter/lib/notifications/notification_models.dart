class AppNotification {
  AppNotification({
    required this.id,
    this.userId,
    required this.title,
    this.body,
    this.readAt,
    required this.createdAt,
    this.createdByName,
  });

  final String id;
  final String? userId;
  final String title;
  final String? body;
  final DateTime? readAt;
  final DateTime createdAt;

  /// Auteur de l'opération à l'origine de la notification (qui a vendu,
  /// saisi la dépense...) — traçabilité, `null` pour une notification
  /// générée automatiquement (alerte de stock bas), sans auteur humain.
  final String? createdByName;

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
        createdByName: json['createdByName'] as String?,
      );
}
