import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../common/formatting.dart';
import 'pos_models.dart';

class ReceiptPage extends StatelessWidget {
  const ReceiptPage({super.key, required this.sale});

  final SaleResult sale;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: const Text('Reçu')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Chez Yasmine',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      dateFormat.format(sale.createdAt.toLocal()),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      'Reçu n° ${sale.id.substring(0, 8)}',
                      textAlign: TextAlign.center,
                    ),
                    if (sale.voidedAt != null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'REMBOURSÉ',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    const Divider(),
                    for (final item in sale.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item.name} x${item.quantity.toStringAsFixed(0)}',
                              ),
                            ),
                            Text(formatAmount(item.quantity * item.unitPrice)),
                          ],
                        ),
                      ),
                    const Divider(),
                    _totalRow('Sous-total', sale.subtotal),
                    if (sale.discount > 0) _totalRow('Remise', -sale.discount),
                    _totalRow('Total', sale.total, bold: true),
                    const SizedBox(height: 8),
                    for (final payment in sale.payments)
                      _totalRow(
                        paymentMethodLabels[payment.method] ?? payment.method,
                        payment.amount,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _totalRow(String label, double amount, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text('${formatAmount(amount)} FCFA', style: style),
        ],
      ),
    );
  }
}
