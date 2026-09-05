import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import 'pending_operation.dart';

class SyncResult {
  SyncResult({required this.synced, required this.failed});
  final int synced;
  final List<String> failed;
}

/// Local offline queue (prompt maître §25-27) : operations captured while
/// offline are stored here, then replayed against
/// `POST /establishments/:id/sync` once connectivity returns. Each entry's
/// id is reused as the entity id server-side, making replay idempotent —
/// see docs/api/sync.md.
class SyncQueueService {
  SyncQueueService(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _prefsKey => 'chez_yasmine_sync_queue_$establishmentId';

  Future<List<PendingOperation>> listPending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => PendingOperation.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _save(List<PendingOperation> operations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(operations.map((o) => o.toJson()).toList()));
  }

  Future<void> enqueue(PendingOperation operation) async {
    final pending = await listPending();
    pending.add(operation);
    await _save(pending);
  }

  /// Sends every queued operation in one batch. On a network failure the
  /// whole queue is left untouched (nothing was necessarily lost server-side
  /// either, since operation ids make replay safe) so a later retry can pick
  /// up where this attempt left off.
  Future<SyncResult> syncAll() async {
    final pending = await listPending();
    if (pending.isEmpty) return SyncResult(synced: 0, failed: []);

    final response = await _api.post('/establishments/$establishmentId/sync', body: {
      'operations': pending
          .map((o) => {'id': o.id, 'entityType': o.entityType, 'deviceId': o.deviceId, 'payload': o.payload})
          .toList(),
    }) as List<dynamic>;

    final remaining = <PendingOperation>[];
    var synced = 0;
    final failed = <String>[];
    for (final entry in response) {
      final result = entry as Map<String, dynamic>;
      final operation = pending.firstWhere((o) => o.id == result['id']);
      if (result['status'] == 'SYNCED') {
        synced++;
      } else {
        failed.add('${operation.entityType} : ${result['error'] ?? result['status']}');
      }
    }
    // Network failure vs. server response are distinguished by the fact that
    // `_api.post` throws before we get here — reaching this point means the
    // server processed the whole batch, so nothing needs to stay queued.
    await _save(remaining);
    return SyncResult(synced: synced, failed: failed);
  }
}
