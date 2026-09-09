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

  /// Même effet que [invite], sans passer par l'e-mail de Supabase (quota
  /// gratuit partagé très limité) — renvoie le lien à copier/transmettre
  /// soi-même par le canal de son choix.
  Future<String> generateInviteLink({required String email, required String roleId, String? fullName}) async {
    final json = await _api.post('$_base/users/invite-link', body: {
      'email': email,
      'roleId': roleId,
      'fullName': ?fullName,
    }) as Map<String, dynamic>;
    return json['link'] as String;
  }

  Future<void> changeRole(String membershipId, String roleId) {
    return _api.patch('$_base/users/$membershipId', body: {'roleId': roleId});
  }

  /// Retire l'utilisateur de cet établissement (révoque son affectation) —
  /// ne supprime jamais son compte Supabase, qui peut appartenir à d'autres
  /// établissements.
  Future<void> removeMember(String membershipId) => _api.delete('$_base/users/$membershipId');
}
