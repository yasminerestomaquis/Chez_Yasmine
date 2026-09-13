import 'dart:async';

import 'package:flutter/material.dart';

import 'connectivity_status.dart';
import 'sync_queue_service.dart';

/// Mounted once, globally, above every screen (see `main.dart`'s
/// `MaterialApp.builder`) — online/offline indicator (rouge hors ligne),
/// pending-operation count, and a manual "Synchroniser" action. Any module
/// can enqueue an offline operation (Caisse, Stock, Dépenses, Tables,
/// Achats, Pertes, Clôture — voir docs/api/sync.md) ; this single instance
/// reflects the shared local queue regardless of which screen is on top.
class SyncStatusBar extends StatefulWidget {
  const SyncStatusBar({super.key, required this.syncQueue});

  final SyncQueueService syncQueue;

  @override
  State<SyncStatusBar> createState() => _SyncStatusBarState();
}

class _SyncStatusBarState extends State<SyncStatusBar> {
  bool _isOnline = true;
  int _pendingCount = 0;
  bool _isSyncing = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    ConnectivityStatus.onlineStream.listen((online) {
      if (!mounted) return;
      setState(() => _isOnline = online);
      if (online) _trySync();
    });
    // Filet de sécurité, en plus de la transition ci-dessus : une opération
    // peut être mise en file par n'importe quel module pendant que cette
    // barre (globale, montée une seule fois) reste affichée sans jamais se
    // recréer — un polling léger garde le compteur à jour et retente une
    // synchronisation automatique sans action de l'utilisateur (demande
    // explicite du 2026-09-13), y compris si la connexion était déjà rétablie
    // avant même l'ouverture de l'application (file laissée par une session
    // précédente).
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final online = await ConnectivityStatus.isOnline();
    final pending = await widget.syncQueue.listPending();
    if (!mounted) return;
    setState(() {
      _isOnline = online;
      _pendingCount = pending.length;
    });
    if (online && pending.isNotEmpty) _trySync();
  }

  Future<void> _trySync() async {
    if (_isSyncing || _pendingCount == 0) return;
    setState(() => _isSyncing = true);
    try {
      final result = await widget.syncQueue.syncAll();
      if (!mounted) return;
      if (result.synced > 0 || result.failed.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            '${result.synced} opération(s) synchronisée(s)'
            '${result.failed.isEmpty ? '' : ', ${result.failed.length} en échec'}',
          ),
        ));
      }
    } catch (_) {
      // Still offline or the server is unreachable — queue stays intact, retried later.
    } finally {
      if (mounted) setState(() => _isSyncing = false);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _isOnline ? Colors.green.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(_isOnline ? Icons.circle : Icons.circle_outlined, size: 10, color: _isOnline ? Colors.green : Colors.red),
            const SizedBox(width: 6),
            Text(
              _isOnline ? 'En ligne' : 'Hors ligne',
              style: TextStyle(fontSize: 12, color: _isOnline ? null : Colors.red.shade900, fontWeight: _isOnline ? null : FontWeight.bold),
            ),
            if (_pendingCount > 0) ...[
              const SizedBox(width: 12),
              Text('$_pendingCount en attente de synchronisation', style: const TextStyle(fontSize: 12)),
              const Spacer(),
              TextButton(
                onPressed: _isSyncing ? null : _trySync,
                child: _isSyncing
                    ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Synchroniser'),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }
}
