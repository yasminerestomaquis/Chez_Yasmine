import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'operation_summary.dart';
import 'pending_operation.dart';
import 'sync_queue_service.dart';

/// Liste des opérations que le serveur a refusées à la synchronisation (stock
/// insuffisant, permission refusée…) — chacune peut être rejouée (par exemple
/// après avoir réapprovisionné le stock) ou supprimée. [onRetry] est appelé
/// après une remise en file pour déclencher une synchronisation aussitôt.
Future<void> showFailedOperationsDialog(
  BuildContext context,
  SyncQueueService queue, {
  VoidCallback? onRetry,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => FailedOperationsDialog(queue: queue, onRetry: onRetry),
  );
}

class FailedOperationsDialog extends StatefulWidget {
  const FailedOperationsDialog({super.key, required this.queue, this.onRetry});

  final SyncQueueService queue;
  final VoidCallback? onRetry;

  @override
  State<FailedOperationsDialog> createState() => _FailedOperationsDialogState();
}

class _FailedOperationsDialogState extends State<FailedOperationsDialog> {
  late Future<List<PendingOperation>> _future = widget.queue.listFailed();

  void _reload() {
    final next = widget.queue.listFailed();
    setState(() {
      _future = next;
    });
  }

  Future<void> _retry(PendingOperation operation) async {
    await widget.queue.retryFailed(operation.id);
    widget.onRetry?.call();
    _reload();
  }

  Future<void> _discard(PendingOperation operation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette opération ?'),
        content: Text(
          '${describeOperation(operation)}\n\nElle ne sera jamais enregistrée sur le serveur. Cette action est définitive.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.queue.discardFailed(operation.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    return AlertDialog(
      title: const Text('Opérations à corriger'),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<List<PendingOperation>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
            }
            final operations = snapshot.data!;
            if (operations.isEmpty) {
              return const Text('Aucune opération à corriger.');
            }
            return ListView.separated(
              shrinkWrap: true,
              itemCount: operations.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final operation = operations[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(describeOperation(operation)),
                  subtitle: Text(
                    'Saisie le ${dateFormat.format(operation.createdAt.toLocal())}\n'
                    '${operation.lastError ?? 'Refusée par le serveur'}',
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Réessayer',
                        icon: const Icon(Icons.replay),
                        onPressed: () => _retry(operation),
                      ),
                      IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _discard(operation),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer')),
      ],
    );
  }
}
