import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'stock_models.dart';
import 'stock_repository.dart';

/// Retourne `true` si un mouvement a été enregistré (pour rafraîchir l'écran appelant).
Future<bool?> showStockMovementDialog(
  BuildContext context, {
  required StockRepository repository,
  required String productId,
  required String productName,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _StockMovementDialog(repository: repository, productId: productId, productName: productName),
  );
}

class _StockMovementDialog extends StatefulWidget {
  const _StockMovementDialog({required this.repository, required this.productId, required this.productName});

  final StockRepository repository;
  final String productId;
  final String productName;

  @override
  State<_StockMovementDialog> createState() => _StockMovementDialogState();
}

class _StockMovementDialogState extends State<_StockMovementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  String _type = 'in';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.repository.createMovement(
        widget.productId,
        type: _type,
        quantity: double.parse(_quantityController.text.trim().replaceAll(',', '.')),
        reason: _reasonController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
              items: stockMovementTypeLabels.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (value) => setState(() => _type = value!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantityController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: _type == 'adjustment' ? 'Nouvelle quantité totale *' : 'Quantité *',
              ),
              validator: (v) {
                final value = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                if (value == null || value < 0) return 'Quantité invalide';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _reasonController, decoration: const InputDecoration(labelText: 'Motif (optionnel)')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
