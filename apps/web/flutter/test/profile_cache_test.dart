import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chez_yasmine/auth/me_repository.dart';
import 'package:chez_yasmine/auth/profile_cache.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('returns null when nothing was ever cached', () async {
    expect(await ProfileCache().load(), isNull);
  });

  test('save then load round-trips id, email, fullName and every establishment', () async {
    final cache = ProfileCache();
    await cache.save(MyProfile(
      id: 'user-1',
      email: 'yaminerestomaquis@gmail.com',
      fullName: 'Yasmine',
      establishments: [
        MyEstablishment(id: 'est-1', name: 'Chez Yasmine', role: 'Propriétaire'),
      ],
    ));

    final reloaded = await cache.load();
    expect(reloaded, isNotNull);
    expect(reloaded!.id, 'user-1');
    expect(reloaded.email, 'yaminerestomaquis@gmail.com');
    expect(reloaded.fullName, 'Yasmine');
    expect(reloaded.establishments, hasLength(1));
    expect(reloaded.establishments.single.id, 'est-1');
    expect(reloaded.establishments.single.name, 'Chez Yasmine');
    expect(reloaded.establishments.single.role, 'Propriétaire');
  });

  test('a later save overwrites the previously cached profile, surviving a fresh ProfileCache instance', () async {
    await ProfileCache().save(MyProfile(id: 'user-1', establishments: []));
    await ProfileCache().save(MyProfile(
      id: 'user-1',
      establishments: [MyEstablishment(id: 'est-2', name: 'Deuxième établissement', role: 'Gérant')],
    ));

    final reloaded = await ProfileCache().load();
    expect(reloaded!.establishments.single.id, 'est-2');
  });
}
