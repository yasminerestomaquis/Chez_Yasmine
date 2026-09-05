import '../api/api_client.dart';

class MyEstablishment {
  MyEstablishment({required this.id, required this.name, required this.role});

  final String id;
  final String name;
  final String role;

  factory MyEstablishment.fromJson(Map<String, dynamic> json) =>
      MyEstablishment(id: json['id'] as String, name: json['name'] as String, role: json['role'] as String);
}

class MyProfile {
  MyProfile({required this.id, this.email, this.fullName, required this.establishments});

  final String id;
  final String? email;
  final String? fullName;
  final List<MyEstablishment> establishments;

  factory MyProfile.fromJson(Map<String, dynamic> json) => MyProfile(
        id: json['id'] as String,
        email: json['email'] as String?,
        fullName: json['fullName'] as String?,
        establishments: (json['establishments'] as List<dynamic>)
            .map((e) => MyEstablishment.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Correspond à GET /auth/me côté NestJS (apps/api/nestjs/src/auth/auth.controller.ts).
class MeRepository {
  MeRepository(this._api);

  final ApiClient _api;

  Future<MyProfile> fetchMe() async {
    final json = await _api.get('/auth/me') as Map<String, dynamic>;
    return MyProfile.fromJson(json);
  }
}
