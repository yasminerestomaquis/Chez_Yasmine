import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../sync/device_id.dart';
import '../sync/pending_operation.dart';
import '../sync/sync_queue_service.dart';
import 'stock_models.dart';
import 'stock_repository.dart';

/// Retourne `true` si un mouvement a été enregistré (pour rafraîchir l'écran appelant).
Future<bool?> showStockMovementDialog(
  BuildContext context, {
  required StockRepository repository,
  required String productId,
  required String productName,
  bool hasVariablePricing = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _StockMovementDialog(
      repository: repository,
      productId: productId,
      productName: productName,
      hasVariablePricing: hasVariablePricing,
    ),
  );
}

class _StockMovementDialog extends StatefulWidget {
  const _StockMovementDialog({
    required this.repository,
    required this.productId,
    required this.productName,
    required this.hasVariablePricing,
  });

  final StockRepository repository;
  final String productId;
  final String productName;
  final bool hasVariablePricing;

  @override
  State<_StockMovementDialog> createState() => _StockMovementDialogState();
}

class _StockMovementDialogState extends State<_StockMovementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  final _marketNumberController = TextEditingController();
  String _type = 'in';
  bool _isSubmitting = false;

  bool get _requiresMarketNumber => widget.hasVariablePricing && _type == 'in';

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    _marketNumberController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final quantity = double.parse(
      _quantityController.text.trim().replaceAll(',', '.'),
    );
    final reason = _reasonController.text.trim();
    final marketNumber = _requiresMarketNumber
        ? int.parse(_marketNumberController.text.trim())
        : null;
    final movementId = const Uuid().v4();

    setState(() => _isSubmitting = true);
    try {
      await widget.repository.createMovement(
        widget.productId,
        type: _type,
        quantity: quantity,
        reason: reason,
        id: movementId,
        marketNumber: marketNumber,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      // A real business rejection (e.g. insufficient stock) — never queued offline.
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      // No HTTP response reached us at all — queue for later sync, keyed by
      // movementId so a retry can never apply the same movement twice.
      final syncQueue = SyncQueueService(
        ApiClient(),
        widget.repository.establishmentId,
      );
      await syncQueue.enqueue(
        PendingOperation(
          id: movementId,
          entityType: 'stock_movement',
          deviceId: await getDeviceId(),
          payload: {
            'productId': widget.productId,
            'type': _type,
            'quantity': quantity,
            if (reason.isNotEmpty) 'reason': reason,
            'marketNumber': ?marketNumber,
          },
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hors ligne : mouvement enregistré localement, il sera synchronisé automatiquement.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Mouvement de stock — ${widget.productName}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              // 'loss' est volontairement exclu ici depuis la Phase 12 : une perte
              // passe désormais par l'écran « Pertes » (losses/), qui écrit à la
              // fois le mouvement de stock et l'enregistrement comptable.
              items: manualStockMovementTypeLabels.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _type = value!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantityController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _type == 'adjustment'
                    ? 'Nouvelle quantité totale *'
                    : 'Quantité *',
              ),
              validator: (v) {
                final value = double.tryParse(
                  (v ?? '').trim().replaceAll(',', '.'),
                );
                if (value == null || value < 0) return 'Quantité invalide';
                return null;
              },
            ),
            if (_requiresMarketNumber) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _marketNumberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'N° de marché *',
                  helperText: 'Doit correspondre à une dépense « Marché » déjà enregistrée',
                ),
                validator: (v) {
                  final value = int.tryParse((v ?? '').trim());
                  if (value == null || value < 1) {
                    return 'N° de marché invalide';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _reasonController,
              decoration: const InputDecoration(labelText: 'Motif (optionnel)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
