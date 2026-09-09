import '../api/api_client.dart';
import 'user_models.dart';

/// Correspond à apps/api/nestjs/src/users/users.controller.ts.
class UsersRepository {
  UsersRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId';

  Future<List<TeamMember>> listTeam() async {
    final json = await _api.get('$_base/users') as List<dynamic>;
    return json.map((e) => TeamMember.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<RoleOption>> listRoles() async {
    final json = await _api.get('$_base/roles') as List<dynamic>;
    return json.map((e) => RoleOption.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> invite({required String email, required String roleId, String? fullName}) {
    return _api.post('$_base/users/invite', body: {'email': email, 'roleId': roleId, 'fullName': ?fullName});
  }
}
