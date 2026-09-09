class RoleOption {
  RoleOption({required this.id, required this.name});

  final String id;
  final String name;

  factory RoleOption.fromJson(Map<String, dynamic> json) =>
      RoleOption(id: json['id'] as String, name: json['name'] as String);
}

class TeamMember {
  TeamMember({required this.userId, required this.fullName, required this.roleId, required this.roleName});

  final String userId;
  final String? fullName;
  final String roleId;
  final String roleName;

  factory TeamMember.fromJson(Map<String, dynamic> json) => TeamMember(
        userId: json['userId'] as String,
        fullName: (json['user'] as Map<String, dynamic>?)?['fullName'] as String?,
        roleId: (json['role'] as Map<String, dynamic>)['id'] as String,
        roleName: (json['role'] as Map<String, dynamic>)['name'] as String,
      );
}
