import 'package:flutter/material.dart';

import 'connectivity_status.dart';
import 'sync_queue_service.dart';

/// Shown at the top of screens that can produce offline operations (POS,
/// stock movements) — online/offline indicator, pending-operation count,
/// and a manual "Synchroniser" action.
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

  @override
  void initState() {
    super.initState();
    _refresh();
    ConnectivityStatus.onlineStream.listen((online) {
      if (!mounted) return;
      setState(() => _isOnline = online);
      if (online) _trySync();
    });
  }

  Future<void> _refresh() async {
    final online = await ConnectivityStatus.isOnline();
    final pending = await widget.syncQueue.listPending();
    if (!mounted) return;
    setState(() {
      _isOnline = online;
      _pendingCount = pending.length;
    });
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
      color: _isOnline ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(_isOnline ? Icons.circle : Icons.circle_outlined, size: 10, color: _isOnline ? Colors.green : Colors.orange),
            const SizedBox(width: 6),
            Text(_isOnline ? 'En ligne' : 'Hors ligne', style: const TextStyle(fontSize: 12)),
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
