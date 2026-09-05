import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'customer_credit_page.dart';
import 'customer_models.dart';
import 'customers_repository.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends State<CustomersPage> {
  late final CustomersRepository _repository = CustomersRepository(ApiClient(), widget.establishmentId);
  late Future<List<Customer>> _future = _repository.listCustomers();

  void _reload() => setState(() => _future = _repository.listCustomers());

  Future<void> _addCustomer() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final creditLimitController = TextEditingController(text: '0');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouveau client'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nom')),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Téléphone')),
            TextField(
              controller: creditLimitController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Plafond de crédit'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Créer')),
        ],
      ),
    );
    if (saved != true || nameController.text.trim().isEmpty) return;
    try {
      await _repository.createCustomer(
        nameController.text.trim(),
        phone: phoneController.text.trim(),
        creditLimit: double.tryParse(creditLimitController.text.trim()) ?? 0,
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clients')),
      body: FutureBuilder<List<Customer>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
            return Center(child: Text(message));
          }
          final customers = snapshot.data!;
          if (customers.isEmpty) {
            return const Center(child: Text('Aucun client — ajoutez-en un avec le bouton +'));
          }
          return ListView(
            children: [
              for (final customer in customers)
                ListTile(
                  title: Text(customer.name),
                  subtitle: Text('${customer.phone ?? ''} — Solde crédit : ${customer.creditBalance.toStringAsFixed(0)} FCFA'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => CustomerCreditPage(repository: _repository, customer: customer)))
                      .then((_) => _reload()),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addCustomer, child: const Icon(Icons.add)),
    );
  }
}
