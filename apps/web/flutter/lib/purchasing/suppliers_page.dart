import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'purchasing_models.dart';
import 'purchasing_repository.dart';

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key, required this.repository});

  final PurchasingRepository repository;

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  late Future<List<Supplier>> _future = widget.repository.listSuppliers();

  void _reload() => setState(() => _future = widget.repository.listSuppliers());

  Future<void> _addSupplier() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouveau fournisseur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nom')),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Téléphone')),
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
      await widget.repository.createSupplier(nameController.text.trim(), phone: phoneController.text.trim());
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fournisseurs')),
      body: FutureBuilder<List<Supplier>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
            return Center(child: Text(message));
          }
          final suppliers = snapshot.data!;
          if (suppliers.isEmpty) {
            return const Center(child: Text('Aucun fournisseur — ajoutez-en un avec le bouton +'));
          }
          return ListView(
            children: [
              for (final supplier in suppliers)
                ListTile(title: Text(supplier.name), subtitle: Text(supplier.phone ?? '')),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addSupplier, child: const Icon(Icons.add)),
    );
  }
}
