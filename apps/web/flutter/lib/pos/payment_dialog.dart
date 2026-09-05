import 'package:flutter/material.dart';

import '../customers/customer_models.dart';
import '../customers/customers_repository.dart';
import 'pos_models.dart';

const _availableMethods = ['cash', 'mobile_money', 'card', 'credit'];

class PaymentLine {
  PaymentLine(this.method, this.amount);
  final String method;
  final double amount;
}

/// A validated payment split, plus the customer to bill if any line is 'credit'.
class PaymentOutcome {
  PaymentOutcome(this.lines, this.customerId);
  final List<PaymentLine> lines;
  final String? customerId;
}

/// Retourne le résultat du paiement (lignes + client si crédit), ou `null` si annulé.
/// [customersRepository] n'est requis que pour proposer le sélecteur de client
/// une fois qu'une ligne « Crédit » est ajoutée.
Future<PaymentOutcome?> showPaymentDialog(
  BuildContext context, {
  required double total,
  required CustomersRepository customersRepository,
}) {
  return showDialog<PaymentOutcome>(
    context: context,
    builder: (_) => _PaymentDialog(total: total, customersRepository: customersRepository),
  );
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.total, required this.customersRepository});
  final double total;
  final CustomersRepository customersRepository;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final List<PaymentLine> _lines = [];
  String _method = _availableMethods.first;
  final _amountController = TextEditingController();
  Customer? _selectedCustomer;
  List<Customer>? _customers;
  bool _customersLoadFailed = false;

  double get _paid => _lines.fold(0, (sum, l) => sum + l.amount);
  double get _remaining => widget.total - _paid;
  bool get _hasCreditLine => _lines.any((l) => l.method == 'credit');

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

  Future<void> _onMethodChanged(String method) async {
    setState(() => _method = method);
    if (method == 'credit' && _customers == null && !_customersLoadFailed) {
      try {
        final customers = await widget.customersRepository.listCustomers();
        if (!mounted) return;
        setState(() => _customers = customers);
      } catch (_) {
        // Leaves _customers null — the "add line" button stays disabled for
        // credit until a customer can actually be picked. Shown inline
        // rather than via ScaffoldMessenger, since this dialog may be shown
        // from a context with no Scaffold ancestor.
        if (!mounted) return;
        setState(() => _customersLoadFailed = true);
      }
    }
  }

  void _addLine() {
    final amount = double.tryParse(_amountController.text.trim().replaceAll(',', '.'));
    if (amount == null || amount <= 0) return;
    if (_method == 'credit' && _selectedCustomer == null) return;
    setState(() {
      _lines.add(PaymentLine(_method, amount));
      final remaining = _remaining;
      _amountController.text = remaining > 0 ? remaining.toStringAsFixed(0) : '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = _method != 'credit' || _selectedCustomer != null;
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
                      onChanged: (v) => _onMethodChanged(v!),
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
              if (_method == 'credit') ...[
                const SizedBox(height: 8),
                if (_customersLoadFailed)
                  const Text('Impossible de charger la liste des clients.', style: TextStyle(color: Colors.red))
                else if (_customers == null)
                  const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
                else
                  DropdownButtonFormField<Customer>(
                    initialValue: _selectedCustomer,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Client *'),
                    items: [
                      for (final customer in _customers!)
                        DropdownMenuItem(value: customer, child: Text(customer.name)),
                    ],
                    onChanged: (c) => setState(() => _selectedCustomer = c),
                  ),
              ],
              const SizedBox(height: 8),
              OutlinedButton(onPressed: canAdd ? _addLine : null, child: const Text('Ajouter la ligne de paiement')),
            ] else
              Text('Restant : ${_remaining.toStringAsFixed(0)} FCFA', style: const TextStyle(color: Colors.green)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _remaining.abs() < 0.01
              ? () => Navigator.of(context).pop(PaymentOutcome(_lines, _hasCreditLine ? _selectedCustomer?.id : null))
              : null,
          child: const Text('Valider le paiement'),
        ),
      ],
    );
  }
}
