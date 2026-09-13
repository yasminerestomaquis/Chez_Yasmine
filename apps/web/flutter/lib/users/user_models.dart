class RoleOption {
  RoleOption({required this.id, required this.name});

  final String id;
  final String name;

  factory RoleOption.fromJson(Map<String, dynamic> json) =>
      RoleOption(id: json['id'] as String, name: json['name'] as String);
}

class TeamMember {
  TeamMember({
    required this.membershipId,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.isOnline,
    required this.lastSeenAt,
    required this.roleId,
    required this.roleName,
  });

  /// Id de l'affectation (UserEstablishmentRole), pas de l'utilisateur —
  /// c'est ce que ciblent PATCH/DELETE .../users/:membershipId.
  final String membershipId;
  final String userId;
  final String? fullName;

  /// Vient de l'API Admin de Supabase côté serveur (`auth.users`, pas
  /// répliqué dans le schéma applicatif) — `null` si introuvable.
  final String? email;

  /// Calculé côté serveur à partir de `lastSeenAt` (< 2 min) — voir
  /// docs/api/users.md. Se rafraîchit donc seulement au rechargement de
  /// cette liste, pas en temps réel pendant qu'elle reste affichée.
  final bool isOnline;

  /// `null` si l'utilisateur n'a jamais fait de requête authentifiée depuis
  /// l'ajout de ce champ (2026-09-13).
  final DateTime? lastSeenAt;
  final String roleId;
  final String roleName;

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    final lastSeenRaw = user?['lastSeenAt'] as String?;
    return TeamMember(
      membershipId: json['id'] as String,
      userId: json['userId'] as String,
      fullName: user?['fullName'] as String?,
      email: user?['email'] as String?,
      isOnline: user?['isOnline'] as bool? ?? false,
      lastSeenAt: lastSeenRaw != null ? DateTime.parse(lastSeenRaw) : null,
      roleId: (json['role'] as Map<String, dynamic>)['id'] as String,
      roleName: (json['role'] as Map<String, dynamic>)['name'] as String,
    );
  }
}
