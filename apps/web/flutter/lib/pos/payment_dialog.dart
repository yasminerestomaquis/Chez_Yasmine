import 'package:flutter/material.dart';

import 'pos_models.dart';

/// Paiement espèces / Mobile Money / carte, y compris mixte (plusieurs lignes).
/// Le crédit sera activé en Phase 11, une fois la gestion des clients en
/// place — l'exposer ici sans sélecteur de client serait trompeur.
const _availableMethods = ['cash', 'mobile_money', 'card'];

class PaymentLine {
  PaymentLine(this.method, this.amount);
  final String method;
  final double amount;
}

/// Retourne les lignes de paiement saisies (somme == [total]), ou `null` si annulé.
Future<List<PaymentLine>?> showPaymentDialog(BuildContext context, {required double total}) {
  return showDialog<List<PaymentLine>>(context: context, builder: (_) => _PaymentDialog(total: total));
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.total});
  final double total;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final List<PaymentLine> _lines = [];
  String _method = _availableMethods.first;
  final _amountController = TextEditingController();

  double get _paid => _lines.fold(0, (sum, l) => sum + l.amount);
  double get _remaining => widget.total - _paid;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.total.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _addLine() {
    final amount = double.tryParse(_amountController.text.trim().replaceAll(',', '.'));
    if (amount == null || amount <= 0) return;
    setState(() {
      _lines.add(PaymentLine(_method, amount));
      final remaining = _remaining;
      _amountController.text = remaining > 0 ? remaining.toStringAsFixed(0) : '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paiement'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total à payer : ${widget.total.toStringAsFixed(0)} FCFA', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            for (final line in _lines)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${paymentMethodLabels[line.method]} : ${line.amount.toStringAsFixed(0)} FCFA'),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _lines.remove(line)),
                ),
              ),
            if (_remaining > 0.009) ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _method,
                      isExpanded: true,
                      items: _availableMethods
                          .map((m) => DropdownMenuItem(value: m, child: Text(paymentMethodLabels[m]!)))
                          .toList(),
                      onChanged: (v) => setState(() => _method = v!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Montant'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _addLine, child: const Text('Ajouter la ligne de paiement')),
            ] else
              Text('Restant : ${_remaining.toStringAsFixed(0)} FCFA', style: const TextStyle(color: Colors.green)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _remaining.abs() < 0.01 ? () => Navigator.of(context).pop(_lines) : null,
          child: const Text('Valider le paiement'),
        ),
      ],
    );
  }
}
