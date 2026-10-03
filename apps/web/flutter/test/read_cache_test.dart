import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chez_yasmine/api/api_client.dart';
import 'package:chez_yasmine/common/read_cache.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final t0 = DateTime.utc(2026, 10, 3, 8, 15);

  test('save puis load restitue le JSON et sa date d\'enregistrement', () async {
    final cache = ReadCache('est-1', now: () => t0);
    await cache.save('tables', [
      {'id': 't1'},
    ]);

    final loaded = await cache.load('tables');

    expect(loaded!.json, [
      {'id': 't1'},
    ]);
    expect(loaded.savedAt, t0);
  });

  test('une copie est propre à son établissement', () async {
    await ReadCache('est-1').save('tables', []);

    expect(await ReadCache('est-2').load('tables'), isNull);
  });

  test('une entrée illisible est ignorée (null) plutôt que de planter', () async {
    SharedPreferences.setMockInitialValues({'chez_yasmine_read_cache_est-1_tables': 'pas du json'});

    expect(await ReadCache('est-1').load('tables'), isNull);
  });

  test('clearAll efface toutes les copies de lecture, tous établissements, sans toucher aux autres données', () async {
    SharedPreferences.setMockInitialValues({'chez_yasmine_sync_queue_est-1': '[]'});
    await ReadCache('est-1').save('customers', []);
    await ReadCache('est-2').save('tables', []);

    await ReadCache.clearAll();

    expect(await ReadCache('est-1').load('customers'), isNull);
    expect(await ReadCache('est-2').load('tables'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('chez_yasmine_sync_queue_est-1'), '[]');
  });

  group('read', () {
    List<String> parse(Object json) => (json as List).cast<String>();

    test('en ligne : donnée fraîche (cachedAt nul), copie enregistrée', () async {
      final cache = ReadCache('est-1', now: () => t0);

      final result = await cache.read(name: 'x', fetch: () async => ['a', 'b'], parse: parse);

      expect(result.value, ['a', 'b']);
      expect(result.cachedAt, isNull);
      expect(result.isStale, isFalse);
      expect((await cache.load('x'))!.json, ['a', 'b']);
    });

    test('serveur injoignable : sert la dernière copie avec sa date', () async {
      final cache = ReadCache('est-1', now: () => t0);
      await cache.save('x', ['ancienne']);

      final result = await cache.read(
        name: 'x',
        fetch: () async => throw http.ClientException('offline'),
        parse: parse,
      );

      expect(result.value, ['ancienne']);
      expect(result.cachedAt, t0);
      expect(result.isStale, isTrue);
    });

    test('serveur injoignable et aucune copie : l\'erreur remonte', () async {
      final cache = ReadCache('est-1');

      await expectLater(
        cache.read(name: 'x', fetch: () async => throw http.ClientException('offline'), parse: parse),
        throwsA(isA<http.ClientException>()),
      );
    });

    test('passerelle indisponible (502/503/504, ex. démarrage à froid) : copie servie', () async {
      final cache = ReadCache('est-1', now: () => t0);
      await cache.save('x', ['ancienne']);

      for (final status in [502, 503, 504]) {
        final result = await cache.read(
          name: 'x',
          fetch: () async => throw ApiException(status, 'Erreur $status'),
          parse: parse,
        );
        expect(result.isStale, isTrue, reason: '$status');
      }
    });

    test('un rejet métier du serveur (400/403/404/500) n\'est JAMAIS masqué par une copie', () async {
      final cache = ReadCache('est-1');
      await cache.save('x', ['ancienne']);

      for (final status in [400, 401, 403, 404, 500]) {
        await expectLater(
          cache.read(name: 'x', fetch: () async => throw ApiException(status, 'Erreur $status'), parse: parse),
          throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', status)),
          reason: '$status',
        );
      }
    });

    test('une lecture en ligne réussie remplace la copie précédente', () async {
      final cache = ReadCache('est-1', now: () => t0);
      await cache.save('x', ['ancienne']);

      await cache.read(name: 'x', fetch: () async => ['nouvelle'], parse: parse);

      expect((await cache.load('x'))!.json, ['nouvelle']);
    });
  });

  test('la copie sérialisée contient bien un JSON valide (format stable)', () async {
    await ReadCache('est-1', now: () => t0).save('tables', [1, 2]);
    final prefs = await SharedPreferences.getInstance();

    final decoded = jsonDecode(prefs.getString('chez_yasmine_read_cache_est-1_tables')!) as Map<String, dynamic>;

    expect(decoded['data'], [1, 2]);
    expect(decoded['savedAt'], '2026-10-03T08:15:00.000Z');
  });
}
