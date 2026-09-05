import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import 'customer_models.dart';
import 'customers_repository.dart';

class CustomerCreditPage extends StatefulWidget {
  const CustomerCreditPage({super.key, required this.repository, required this.customer});

  final CustomersRepository repository;
  final Customer customer;

  @override
  State<CustomerCreditPage> createState() => _CustomerCreditPageState();
}

class _CustomerCreditPageState extends State<CustomerCreditPage> {
  late Future<List<CreditHistoryEntry>> _future = widget.repository.creditHistory(widget.customer.id);
  bool _isSubmitting = false;

  void _reload() => setState(() => _future = widget.repository.creditHistory(widget.customer.id));

  Future<void> _addRepayment() async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enregistrer un remboursement'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Montant (solde actuel : ${widget.customer.creditBalance.toStringAsFixed(0)} FCFA)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(double.tryParse(controller.text.trim().replaceAll(',', '.'))),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (amount == null || amount <= 0) return;

    setState(() => _isSubmitting = true);
    try {
      await widget.repository.recordRepayment(widget.customer.id, amount);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: Text('Crédit — ${widget.customer.name}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(child: Text('Solde : ${widget.customer.creditBalance.toStringAsFixed(0)} FCFA')),
                    Expanded(child: Text('Plafond : ${widget.customer.creditLimit.toStringAsFixed(0)} FCFA')),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<CreditHistoryEntry>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('${snapshot.error}'));
                }
                final entries = snapshot.data!;
                if (entries.isEmpty) {
                  return const Center(child: Text('Aucun mouvement de crédit.'));
                }
                return ListView(
                  children: [
                    for (final entry in entries)
                      ListTile(
                        leading: Icon(entry.type == 'credit' ? Icons.arrow_upward : Icons.arrow_downward,
                            color: entry.type == 'credit' ? Colors.red : Colors.green),
                        title: Text(entry.type == 'credit' ? 'Vente à crédit' : 'Remboursement'),
                        subtitle: Text(dateFormat.format(entry.createdAt.toLocal())),
                        trailing: Text('${entry.amount.toStringAsFixed(0)} FCFA'),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSubmitting ? null : _addRepayment,
        icon: const Icon(Icons.payments_outlined),
        label: const Text('Remboursement'),
      ),
    );
  }
}
