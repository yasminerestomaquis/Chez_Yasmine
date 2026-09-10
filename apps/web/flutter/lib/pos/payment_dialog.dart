import 'package:flutter/material.dart';

import '../common/formatting.dart';
import 'pos_models.dart';

// Décision explicite de l'utilisateur (2026-09-10) : "Carte" et "Crédit"
// retirés des modes de paiement proposés à l'encaissement — seuls Espèces et
// Mobile Money restent sélectionnables. Le suivi des créances client
// existantes (module Clients, `credits.service.ts` côté API) n'est pas
// touché : seule la création d'une NOUVELLE vente à crédit depuis ce
// dialogue n'est plus possible.
const _availableMethods = ['cash', 'mobile_money'];

class PaymentLine {
  PaymentLine(this.method, this.amount);
  final String method;
  final double amount;
}

/// Un paiement validé (une ou plusieurs lignes couvrant le total), avec le
/// N° de commande/N° de marché éventuellement rattachés à cette vente — voir
/// `docs/api/pos.md`.
class PaymentOutcome {
  PaymentOutcome(this.lines, {this.orderNumber, this.marketNumber});
  final List<PaymentLine> lines;
  final int? orderNumber;
  final int? marketNumber;
}

/// Retourne le résultat du paiement, ou `null` si annulé.
///
/// [showOrderNumberField]/[showMarketNumberField] affichent respectivement le
/// champ N° de la commande (panier contenant un produit Bières/Vins/
/// Sucreries) et N° de marché (panier contenant un produit Poulets/Poissons/
/// Plats africains) — pré-remplis via [fetchLastOrderNumber]/
/// [fetchLastMarketNumber] (simple suggestion de convenance, jamais
/// bloquante), librement éditables.
Future<PaymentOutcome?> showPaymentDialog(
  BuildContext context, {
  required double total,
  bool showOrderNumberField = false,
  bool showMarketNumberField = false,
  Future<int?> Function()? fetchLastOrderNumber,
  Future<int?> Function()? fetchLastMarketNumber,
}) {
  return showDialog<PaymentOutcome>(
    context: context,
    builder: (_) => _PaymentDialog(
      total: total,
      showOrderNumberField: showOrderNumberField,
      showMarketNumberField: showMarketNumberField,
      fetchLastOrderNumber: fetchLastOrderNumber,
      fetchLastMarketNumber: fetchLastMarketNumber,
    ),
  );
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.total,
    required this.showOrderNumberField,
    required this.showMarketNumberField,
    this.fetchLastOrderNumber,
    this.fetchLastMarketNumber,
  });
  final double total;
  final bool showOrderNumberField;
  final bool showMarketNumberField;
  final Future<int?> Function()? fetchLastOrderNumber;
  final Future<int?> Function()? fetchLastMarketNumber;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final List<PaymentLine> _lines = [];
  String _method = _availableMethods.first;
  final _amountController = TextEditingController();
  final _orderNumberController = TextEditingController();
  final _marketNumberController = TextEditingController();

  double get _paid => _lines.fold(0, (sum, l) => sum + l.amount);
  double get _remaining => widget.total - _paid;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.total.toStringAsFixed(0);
    if (widget.showOrderNumberField) _loadLastOrderNumber();
    if (widget.showMarketNumberField) _loadLastMarketNumber();
  }

  Future<void> _loadLastOrderNumber() async {
    try {
      final last = await widget.fetchLastOrderNumber?.call();
      if (last == null || !mounted) return;
      setState(() => _orderNumberController.text = '$last');
    } catch (_) {
      // Simple suggestion de convenance — jamais bloquant, saisie manuelle toujours possible.
    }
  }

  Future<void> _loadLastMarketNumber() async {
    try {
      final last = await widget.fetchLastMarketNumber?.call();
      if (last == null || !mounted) return;
      setState(() => _marketNumberController.text = '$last');
    } catch (_) {
      // Simple suggestion de convenance — jamais bloquant, saisie manuelle toujours possible.
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _orderNumberController.dispose();
    _marketNumberController.dispose();
    super.dispose();
  }

  void _addLine() {
    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) return;
    setState(() {
      _lines.add(PaymentLine(_method, amount));
      final remaining = _remaining;
      _amountController.text = remaining > 0
          ? remaining.toStringAsFixed(0)
          : '';
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
            Text(
              'Total à payer : ${formatAmount(widget.total)} FCFA',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (widget.showOrderNumberField) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _orderNumberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'N° de la commande',
                ),
              ),
            ],
            if (widget.showMarketNumberField) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _marketNumberController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'N° de marché'),
              ),
            ],
            const SizedBox(height: 12),
            for (final line in _lines)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${paymentMethodLabels[line.method]} : ${formatAmount(line.amount)} FCFA',
                ),
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
                          .map(
                            (m) => DropdownMenuItem(
                              value: m,
                              child: Text(paymentMethodLabels[m]!),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _method = v!),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Montant'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _addLine,
                child: const Text('Ajouter la ligne de paiement'),
              ),
            ] else
              Text(
                'Restant : ${formatAmount(_remaining)} FCFA',
                style: const TextStyle(color: Colors.green),
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
          onPressed: _remaining.abs() < 0.01
              ? () => Navigator.of(context).pop(
                  PaymentOutcome(
                    _lines,
                    orderNumber: int.tryParse(
                      _orderNumberController.text.trim(),
                    ),
                    marketNumber: int.tryParse(
                      _marketNumberController.text.trim(),
                    ),
                  ),
                )
              : null,
          child: const Text('Valider le paiement'),
        ),
      ],
    );
  }
}
