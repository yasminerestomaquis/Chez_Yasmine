import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_client.dart';
import 'pending_operation.dart';

class SyncResult {
  SyncResult({required this.synced, required this.failed});
  final int synced;
  final List<String> failed;
}

typedef SessionRefresher = Future<void> Function({bool force});

/// Renouvelle le jeton Supabase avant d'écrire à l'API : après une longue
/// période hors ligne, le jeton d'accès (≈ 1 h) est expiré et le
/// renouvellement automatique n'a pas pu s'exécuter. `force` : renouvelle même
/// si le jeton paraît encore valide (réponse 401 du serveur). Une erreur ici
/// est sans conséquence en soi — si le jeton reste invalide, c'est la
/// réponse 401 de l'API qui le fera savoir.
Future<void> _refreshSupabaseSession({bool force = false}) async {
  try {
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;
    if (session == null) return;
    if (!force) {
      final expiresAt = session.expiresAt;
      if (expiresAt == null) return;
      final soon = DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000;
      if (expiresAt > soon) return;
    }
    await auth.refreshSession();
  } catch (_) {}
}

/// Local offline queue (prompt maître §25-27) : operations captured while
/// offline are stored here, then replayed against
/// `POST /establishments/:id/sync` once connectivity returns. Each entry's
/// id is reused as the entity id server-side, making replay idempotent —
/// see docs/api/sync.md.
class SyncQueueService {
  SyncQueueService(this._api, this.establishmentId, {SessionRefresher? refreshSession})
      : _refreshSession = refreshSession ?? _refreshSupabaseSession;

  final ApiClient _api;
  final String establishmentId;
  final SessionRefresher _refreshSession;

  String get _prefsKey => 'chez_yasmine_sync_queue_$establishmentId';

  /// Opérations que le serveur a refusées (stock insuffisant, permission
  /// refusée…) : conservées ici pour être corrigées ou supprimées par
  /// l'utilisateur plutôt que de disparaître en silence.
  String get _failedKey => 'chez_yasmine_sync_failed_$establishmentId';

  Future<List<PendingOperation>> _load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => PendingOperation.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> _store(String key, List<PendingOperation> operations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(operations.map((o) => o.toJson()).toList()));
  }

  Future<List<PendingOperation>> listPending() => _load(_prefsKey);

  Future<List<PendingOperation>> listFailed() => _load(_failedKey);

  Future<void> _save(List<PendingOperation> operations) => _store(_prefsKey, operations);

  Future<void> enqueue(PendingOperation operation) async {
    final pending = await listPending();
    pending.add(operation);
    await _save(pending);
  }

  /// Remet une opération refusée en file d'attente pour un nouvel essai (elle
  /// garde son identifiant : le serveur la rejoue sans risque de doublon, et
  /// son heure de saisie d'origine).
  Future<void> retryFailed(String id) async {
    final failed = await listFailed();
    final index = failed.indexWhere((o) => o.id == id);
    if (index == -1) return;
    final operation = failed.removeAt(index);
    final pending = await listPending();
    if (!pending.any((o) => o.id == id)) pending.add(operation);
    await _save(pending);
    await _store(_failedKey, failed);
  }

  Future<void> discardFailed(String id) async {
    final failed = await listFailed();
    failed.removeWhere((o) => o.id == id);
    await _store(_failedKey, failed);
  }

  /// Mémorise les opérations refusées (une seule entrée par identifiant : un
  /// nouvel échec met à jour la précédente).
  Future<void> _recordFailed(List<PendingOperation> rejected) async {
    if (rejected.isEmpty) return;
    final failed = await listFailed();
    for (final operation in rejected) {
      failed.removeWhere((o) => o.id == operation.id);
      failed.add(operation);
    }
    await _store(_failedKey, failed);
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

  Future<List<dynamic>> _postChunk(List<PendingOperation> chunk) async {
    Future<dynamic> post() => _api.post('/establishments/$establishmentId/sync', body: {
          'operations': chunk
              .map((o) => {
                    'id': o.id,
                    'entityType': o.entityType,
                    'deviceId': o.deviceId,
                    'payload': o.payload,
                    // Heure réelle de saisie sur l'appareil : sans elle, le serveur
                    // daterait l'opération de sa synchronisation.
                    'capturedAt': o.createdAt.toUtc().toIso8601String(),
                  })
              .toList(),
        });
    try {
      return await post() as List<dynamic>;
    } on ApiException catch (e) {
      if (e.statusCode != 401) rethrow;
      // Jeton refusé : un renouvellement forcé, puis un seul nouvel essai.
      await _refreshSession(force: true);
      return await post() as List<dynamic>;
    }
  }

  /// Sends every queued operation, chunked to respect the server's batch
  /// size limit. Each chunk is removed from the persisted queue only once
  /// its own response is received — a later chunk failing (or the
  /// connection dropping partway through) never discards an earlier chunk
  /// that already synced, and leaves the rest queued for the next attempt.
  /// Resending an already-processed chunk on a later retry is always safe:
  /// every entity this dispatches to is idempotent on the operation's id
  /// (see docs/api/sync.md).
  ///
  /// Une opération refusée par le serveur (FAILED/CONFLICT) quitte la file
  /// mais est conservée dans la liste « à corriger » ([listFailed]).
  Future<SyncResult> syncAll() async {
    var pending = await listPending();
    if (pending.isEmpty) return SyncResult(synced: 0, failed: []);

    await _refreshSession(force: false);

    var synced = 0;
    final failed = <String>[];
    while (pending.isNotEmpty) {
      final chunk = pending.take(_maxBatchSize).toList();
      final response = await _postChunk(chunk);

      final rejected = <PendingOperation>[];
      for (final entry in response) {
        final result = entry as Map<String, dynamic>;
        final operation = chunk.firstWhere((o) => o.id == result['id']);
        if (result['status'] == 'SYNCED') {
          synced++;
        } else {
          final reason = '${result['error'] ?? result['status']}';
          failed.add('${operation.entityType} : $reason');
          operation
            ..attemptCount += 1
            ..lastError = reason;
          rejected.add(operation);
        }
      }
      // Ce morceau a reçu une réponse pour chacune de ses opérations
      // (SYNCED, FAILED ou CONFLICT) : aucune n'a plus besoin de rester en
      // file d'attente. Un rejet métier ne deviendrait jamais un succès en le
      // rejouant tel quel, mais il n'est plus jamais perdu : enregistré dans
      // la liste « à corriger » AVANT d'être retiré de la file (un arrêt
      // entre les deux écritures laisse l'opération dans les deux listes, ce
      // que le prochain passage résout sans doublon — même identifiant). Une
      // exception avant ce point laisse ce morceau ET tous les suivants
      // intacts en file pour le prochain essai.
      await _recordFailed(rejected);
      pending = pending.skip(chunk.length).toList();
      await _save(pending);
    }
    return SyncResult(synced: synced, failed: failed);
  }
}
