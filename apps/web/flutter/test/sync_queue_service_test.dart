import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/api/api_client.dart';
import 'package:chez_yasmine/sync/pending_operation.dart';
import 'package:chez_yasmine/sync/sync_queue_service.dart';

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
}
