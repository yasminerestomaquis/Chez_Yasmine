import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../common/formatting.dart';
import '../common/offline_banner.dart';
import '../common/read_cache.dart';
import '../sync/connectivity_status.dart';
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
  late Future<Cached<List<Customer>>> _future = _repository.loadCustomers();
  StreamSubscription<bool>? _reconnectSubscription;

  @override
  void initState() {
    super.initState();
    _reconnectSubscription = ConnectivityStatus.onReconnect(() {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _reconnectSubscription?.cancel();
    super.dispose();
  }

  void _reload() {
    final next = _repository.loadCustomers();
    setState(() {
      _future = next;
    });
  }

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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur réseau — client non créé (la création exige une connexion)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clients')),
      body: FutureBuilder<Cached<List<Customer>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
            return Center(child: Text(message));
          }
          final cached = snapshot.data!;
          final customers = cached.value;
          if (customers.isEmpty) {
            return const Center(child: Text('Aucun client — ajoutez-en un avec le bouton +'));
          }
          return ListView(
            children: [
              if (cached.cachedAt != null) OfflineBanner(cachedAt: cached.cachedAt!, onRefresh: _reload),
              for (final customer in customers)
                ListTile(
                  title: Text(customer.name),
                  subtitle: Text('${customer.phone ?? ''} — Solde crédit : ${formatAmount(customer.creditBalance)} FCFA'),
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
