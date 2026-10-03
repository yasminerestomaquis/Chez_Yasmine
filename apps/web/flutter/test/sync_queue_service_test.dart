import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/api/api_client.dart';
import 'package:chez_yasmine/sync/pending_operation.dart';
import 'package:chez_yasmine/sync/sync_queue_service.dart';

Future<void> _noRefresh({bool force = false}) async {}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a queue starts empty', () async {
    final queue = SyncQueueService(ApiClient(), 'est-1');
    expect(await queue.listPending(), isEmpty);
  });

  test('enqueue persists the operation, surviving a fresh SyncQueueService instance', () async {
    final queue = SyncQueueService(ApiClient(), 'est-1');
    await queue.enqueue(PendingOperation(
      id: 'op-1',
      entityType: 'sale',
      deviceId: 'device-1',
      payload: {'items': []},
      createdAt: DateTime.utc(2026, 1, 1),
    ));

    // A brand new instance reads from the same underlying storage.
    final reloaded = await SyncQueueService(ApiClient(), 'est-1').listPending();
    expect(reloaded, hasLength(1));
    expect(reloaded.single.id, 'op-1');
    expect(reloaded.single.entityType, 'sale');
    expect(reloaded.single.payload, {'items': []});
  });

  test('queues for different establishments do not interfere with each other', () async {
    final queueA = SyncQueueService(ApiClient(), 'est-A');
    final queueB = SyncQueueService(ApiClient(), 'est-B');

    await queueA.enqueue(PendingOperation(
      id: 'op-a',
      entityType: 'sale',
      deviceId: 'device-1',
      payload: const {},
      createdAt: DateTime.now(),
    ));

    expect(await queueA.listPending(), hasLength(1));
    expect(await queueB.listPending(), isEmpty);
  });

  test('multiple operations enqueue in order', () async {
    final queue = SyncQueueService(ApiClient(), 'est-1');
    for (final id in ['op-1', 'op-2', 'op-3']) {
      await queue.enqueue(PendingOperation(
        id: id,
        entityType: 'stock_movement',
        deviceId: 'device-1',
        payload: const {'productId': 'p1', 'type': 'in', 'quantity': 1},
        createdAt: DateTime.now(),
      ));
    }

    final pending = await queue.listPending();
    expect(pending.map((o) => o.id).toList(), ['op-1', 'op-2', 'op-3']);
  });

  group('syncAll — heure de saisie, opérations refusées, jeton (2026-10-03)', () {
    PendingOperation op(String id, {String type = 'sale', DateTime? createdAt}) => PendingOperation(
          id: id,
          entityType: type,
          deviceId: 'device-1',
          payload: {
            'payments': [
              {'method': 'cash', 'amount': 1000},
            ],
          },
          createdAt: createdAt ?? DateTime.utc(2026, 10, 2, 18, 30),
        );

    Future<T> withServer<T>(Future<T> Function() body, http.Response Function(http.Request request) handler) {
      return http.runWithClient(body, () => MockClient((request) async => handler(request)));
    }

    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

    SyncQueueService newQueue() => SyncQueueService(ApiClient(), 'est-1', refreshSession: _noRefresh);

    test('chaque opération part avec son heure de saisie réelle (capturedAt), pas celle de la synchronisation', () async {
      final queue = newQueue();
      await queue.enqueue(op('op-1', createdAt: DateTime.utc(2026, 10, 2, 18, 30)));
      Map<String, dynamic>? sent;

      final result = await withServer(queue.syncAll, (request) {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return json([
          {'id': 'op-1', 'status': 'SYNCED'},
        ]);
      });

      expect(result.synced, 1);
      final operation = (sent!['operations'] as List).single as Map<String, dynamic>;
      expect(operation['capturedAt'], '2026-10-02T18:30:00.000Z');
      expect(await queue.listPending(), isEmpty);
      expect(await queue.listFailed(), isEmpty);
    });

    test('une opération refusée par le serveur n\'est plus perdue : elle va dans la liste « à corriger » avec son motif', () async {
      final queue = newQueue();
      await queue.enqueue(op('ok'));
      await queue.enqueue(op('refusee'));
      await queue.enqueue(op('interdite', type: 'stock_movement'));

      final result = await withServer(
        queue.syncAll,
        (_) => json([
          {'id': 'ok', 'status': 'SYNCED'},
          {'id': 'refusee', 'status': 'CONFLICT', 'error': 'Stock insuffisant pour Celtia'},
          {'id': 'interdite', 'status': 'FAILED', 'error': 'Permission refusée pour cette opération'},
        ]),
      );

      expect(result.synced, 1);
      expect(result.failed, hasLength(2));
      expect(await queue.listPending(), isEmpty);
      final failed = await queue.listFailed();
      expect(failed.map((o) => o.id), ['refusee', 'interdite']);
      expect(failed.first.lastError, 'Stock insuffisant pour Celtia');
      expect(failed.first.attemptCount, 1);
      expect(failed.first.createdAt, DateTime.utc(2026, 10, 2, 18, 30), reason: 'l\'heure de saisie d\'origine est conservée');
    });

    test('la liste « à corriger » survit à une nouvelle instance (persistée)', () async {
      final queue = newQueue();
      await queue.enqueue(op('refusee'));
      await withServer(
        queue.syncAll,
        (_) => json([
          {'id': 'refusee', 'status': 'CONFLICT', 'error': 'x'},
        ]),
      );

      final reloaded = await SyncQueueService(ApiClient(), 'est-1').listFailed();

      expect(reloaded.single.id, 'refusee');
    });

    test('Réessayer remet l\'opération en file ; un nouvel échec met l\'entrée à jour sans doublon', () async {
      final queue = newQueue();
      await queue.enqueue(op('refusee'));
      await withServer(
        queue.syncAll,
        (_) => json([
          {'id': 'refusee', 'status': 'CONFLICT', 'error': 'Stock insuffisant'},
        ]),
      );

      await queue.retryFailed('refusee');
      expect(await queue.listFailed(), isEmpty);
      expect((await queue.listPending()).single.id, 'refusee');

      await withServer(
        queue.syncAll,
        (_) => json([
          {'id': 'refusee', 'status': 'CONFLICT', 'error': 'Encore insuffisant'},
        ]),
      );
      final failed = await queue.listFailed();
      expect(failed, hasLength(1));
      expect(failed.single.lastError, 'Encore insuffisant');
      expect(failed.single.attemptCount, 2);
    });

    test('Réessayer puis succès : plus rien en file ni à corriger', () async {
      final queue = newQueue();
      await queue.enqueue(op('refusee'));
      await withServer(
        queue.syncAll,
        (_) => json([
          {'id': 'refusee', 'status': 'CONFLICT', 'error': 'Stock insuffisant'},
        ]),
      );
      await queue.retryFailed('refusee');

      final result = await withServer(
        queue.syncAll,
        (_) => json([
          {'id': 'refusee', 'status': 'SYNCED'},
        ]),
      );

      expect(result.synced, 1);
      expect(await queue.listPending(), isEmpty);
      expect(await queue.listFailed(), isEmpty);
    });

    test('Supprimer retire définitivement une opération à corriger', () async {
      final queue = newQueue();
      await queue.enqueue(op('a'));
      await queue.enqueue(op('b'));
      await withServer(
        queue.syncAll,
        (_) => json([
          {'id': 'a', 'status': 'CONFLICT', 'error': 'x'},
          {'id': 'b', 'status': 'CONFLICT', 'error': 'y'},
        ]),
      );

      await queue.discardFailed('a');

      expect((await queue.listFailed()).map((o) => o.id), ['b']);
    });

    test('une coupure réseau en cours de synchro laisse la file intacte et ne crée aucune opération « à corriger »', () async {
      final queue = newQueue();
      await queue.enqueue(op('op-1'));

      await expectLater(
        http.runWithClient(queue.syncAll, () => MockClient((_) async => throw http.ClientException('offline'))),
        throwsA(isA<http.ClientException>()),
      );

      expect(await queue.listPending(), hasLength(1));
      expect(await queue.listFailed(), isEmpty);
    });

    test('le jeton est vérifié avant l\'envoi ; sur une file vide, aucun appel', () async {
      var checks = 0;
      final queue = SyncQueueService(
        ApiClient(),
        'est-1',
        refreshSession: ({bool force = false}) async => checks++,
      );

      await queue.syncAll();
      expect(checks, 0);

      await queue.enqueue(op('op-1'));
      await withServer(
        queue.syncAll,
        (_) => json([
          {'id': 'op-1', 'status': 'SYNCED'},
        ]),
      );
      expect(checks, 1);
    });

    test('401 : renouvellement forcé du jeton puis un seul nouvel essai, qui aboutit', () async {
      final forced = <bool>[];
      final queue = SyncQueueService(
        ApiClient(),
        'est-1',
        refreshSession: ({bool force = false}) async => forced.add(force),
      );
      await queue.enqueue(op('op-1'));
      var calls = 0;

      final result = await withServer(queue.syncAll, (_) {
        calls++;
        return calls == 1
            ? json({'message': 'Unauthorized'}, 401)
            : json([
                {'id': 'op-1', 'status': 'SYNCED'},
              ]);
      });

      expect(result.synced, 1);
      expect(calls, 2);
      expect(forced, [false, true]);
      expect(await queue.listPending(), isEmpty);
    });

    test('401 persistant (session perdue) : ApiException, file intacte pour après la reconnexion', () async {
      final queue = newQueue();
      await queue.enqueue(op('op-1'));
      var calls = 0;

      await expectLater(
        withServer(queue.syncAll, (_) {
          calls++;
          return json({'message': 'Unauthorized'}, 401);
        }),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
      );

      expect(calls, 2, reason: 'un seul nouvel essai');
      expect(await queue.listPending(), hasLength(1));
      expect(await queue.listFailed(), isEmpty);
    });
  });
}
