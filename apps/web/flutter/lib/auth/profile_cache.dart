import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'me_repository.dart';

/// Lets the app reopen offline (prompt maître §25) past the very first gate
/// of `HomePage` (`GET /auth/me`, needed to know which establishment to show)
/// — the last successful profile is cached locally and served back if a
/// later fetch fails. Same pattern as `CatalogCache`, but not scoped per
/// establishment: at this point in the app, which establishment the user
/// belongs to is exactly what this call is meant to answer.
class ProfileCache {
  static const _key = 'chez_yasmine_profile_cache';

  Future<void> save(MyProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'id': profile.id,
        'email': profile.email,
        'fullName': profile.fullName,
        'establishments': profile.establishments
            .map((e) => {'id': e.id, 'name': e.name, 'role': e.role})
            .toList(),
      }),
    );
  }

  Future<MyProfile?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return MyProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}
