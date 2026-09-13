import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../common/formatting.dart';
import '../sync/device_id.dart';
import '../sync/pending_operation.dart';
import '../sync/sync_queue_service.dart';
import 'cash_models.dart';
import 'cash_repository.dart';

class CashPage extends StatefulWidget {
  const CashPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<CashPage> createState() => _CashPageState();
}

class _CashPageState extends State<CashPage> {
  late final CashRepository _repository = CashRepository(ApiClient(), widget.establishmentId);
  late final SyncQueueService _syncQueue = SyncQueueService(ApiClient(), widget.establishmentId);
  late Future<List<CashClosing>> _future = _repository.listClosings();

  void _reload() => setState(() => _future = _repository.listClosings());

  Future<void> _openClosingDialog() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    var openedAt = startOfDay;
    final countedController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? error;

    final closed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Clôture de caisse'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ouverte depuis'),
                  subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(openedAt)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: openedAt,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setDialogState(() => openedAt = picked);
                  },
                ),
                TextFormField(
                  controller: countedController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Montant compté en caisse *'),
                  validator: (v) {
                    final value = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                    if (value == null || value < 0) return 'Montant invalide';
                    return null;
                  },
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final closingId = const Uuid().v4();
                final countedAmount = double.parse(countedController.text.trim().replaceAll(',', '.'));
                try {
                  await _repository.close(id: closingId, openedAt: openedAt, countedAmount: countedAmount);
                  if (context.mounted) Navigator.of(context).pop(true);
                } on ApiException catch (e) {
                  // Rejet métier réel — rejouer ne changerait rien, jamais mis en file.
                  setDialogState(() => error = e.message);
                } catch (_) {
                  // Aucune réponse HTTP reçue — coupure réseau : mise en file,
                  // rejouée via SyncService (`entityType: 'cash_closing'`) au
                  // retour du réseau.
                  await _syncQueue.enqueue(
                    PendingOperation(
                      id: closingId,
                      entityType: 'cash_closing',
                      deviceId: await getDeviceId(),
                      payload: {'openedAt': openedAt.toUtc().toIso8601String(), 'countedAmount': countedAmount},
                      createdAt: DateTime.now(),
                    ),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Hors ligne : clôture enregistrée localement, elle sera synchronisée automatiquement.',
                      ),
                    ),
                  );
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text('Clôturer'),
            ),
          ],
        ),
      ),
    );
    if (closed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Caisse')),
      body: FutureBuilder<List<CashClosing>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
            return Center(child: Text(message));
          }
          final closings = snapshot.data!;
          if (closings.isEmpty) {
            return const Center(child: Text('Aucune clôture — utilisez le bouton +'));
          }
          return ListView(
            children: [
              for (final closing in closings)
                ListTile(
                  title: Text('Attendu ${formatAmount(closing.expectedAmount)} — Compté ${formatAmount(closing.countedAmount)} FCFA'),
                  subtitle: Text('Clôturée le ${dateFormat.format(closing.closedAt.toLocal())}'),
                  trailing: Text(
                    '${closing.difference >= 0 ? '+' : ''}${formatAmount(closing.difference)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: closing.difference == 0 ? null : (closing.difference > 0 ? Colors.green : Colors.red),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _openClosingDialog, child: const Icon(Icons.point_of_sale)),
    );
  }
}
