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

  /// The backend caps a single batch at 100 operations (`SyncBatchDto`,
  /// `@ArrayMaxSize(100)`) — a long enough offline period spanning several
  /// modules (Caisse, Tables, Stock, Dépenses, Achats, Pertes, Clôture)
  /// could plausibly queue more than that. Sending the whole queue past this
  /// size in one request would make the server reject it outright (400),
  /// leaving `syncAll()` permanently unable to make progress — exactly the
  /// data-loss-by-being-stuck scenario the manual "Synchroniser" button must
  /// never produce (décision actée 2026-09-13).
  static const _maxBatchSize = 100;

  /// Sends every queued operation, chunked to respect the server's batch
  /// size limit. Each chunk is removed from the persisted queue only once
  /// its own response is received — a later chunk failing (or the
  /// connection dropping partway through) never discards an earlier chunk
  /// that already synced, and leaves the rest queued for the next attempt.
  /// Resending an already-processed chunk on a later retry is always safe:
  /// every entity this dispatches to is idempotent on the operation's id
  /// (see docs/api/sync.md).
  Future<SyncResult> syncAll() async {
    var pending = await listPending();
    if (pending.isEmpty) return SyncResult(synced: 0, failed: []);

    var synced = 0;
    final failed = <String>[];
    while (pending.isNotEmpty) {
      final chunk = pending.take(_maxBatchSize).toList();
      final response = await _api.post('/establishments/$establishmentId/sync', body: {
        'operations': chunk
            .map((o) => {'id': o.id, 'entityType': o.entityType, 'deviceId': o.deviceId, 'payload': o.payload})
            .toList(),
      }) as List<dynamic>;

      for (final entry in response) {
        final result = entry as Map<String, dynamic>;
        final operation = chunk.firstWhere((o) => o.id == result['id']);
        if (result['status'] == 'SYNCED') {
          synced++;
        } else {
          failed.add('${operation.entityType} : ${result['error'] ?? result['status']}');
        }
      }
      // Ce morceau a reçu une réponse pour chacune de ses opérations
      // (SYNCED, FAILED ou CONFLICT) : aucune n'a plus besoin de rester en
      // file, qu'elle ait réussi ou non — un rejet métier ne deviendrait
      // jamais un succès en le rejouant tel quel (même principe que le
      // reste de l'application). Une exception avant ce point laisse ce
      // morceau ET tous les suivants intacts en file pour le prochain essai.
      pending = pending.skip(chunk.length).toList();
      await _save(pending);
    }
    return SyncResult(synced: synced, failed: failed);
  }
}
