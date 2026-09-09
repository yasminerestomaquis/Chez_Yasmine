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

  Future<_SupplierFormResult?> _showSupplierDialog({
    required String title,
    String? initialName,
    String? initialPhone,
    String? initialAddress,
  }) {
    final nameController = TextEditingController(text: initialName ?? '');
    final phoneController = TextEditingController(text: initialPhone ?? '');
    final addressController = TextEditingController(text: initialAddress ?? '');
    return showDialog<_SupplierFormResult>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, autofocus: true, decoration: const InputDecoration(labelText: 'Nom')),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Téléphone')),
            TextField(controller: addressController, decoration: const InputDecoration(labelText: 'Adresse')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.of(context).pop(_SupplierFormResult(
                name: name,
                phone: phoneController.text.trim(),
                address: addressController.text.trim(),
              ));
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  Future<void> _addSupplier() async {
    final result = await _showSupplierDialog(title: 'Nouveau fournisseur');
    if (result == null) return;
    try {
      await widget.repository.createSupplier(result.name, phone: result.phone, address: result.address);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _editSupplier(Supplier supplier) async {
    final result = await _showSupplierDialog(
      title: 'Modifier le fournisseur',
      initialName: supplier.name,
      initialPhone: supplier.phone,
      initialAddress: supplier.address,
    );
    if (result == null) return;
    try {
      await widget.repository.updateSupplier(supplier.id, name: result.name, phone: result.phone, address: result.address);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteSupplier(Supplier supplier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce fournisseur ?'),
        content: Text(
          '« ${supplier.name} » sera supprimé. Les achats déjà enregistrés avec ce fournisseur sont conservés '
          '(ils affichent simplement « Fournisseur non renseigné » ensuite).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteSupplier(supplier.id);
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
                ListTile(
                  title: Text(supplier.name),
                  subtitle: Text([?supplier.phone, ?supplier.address].where((s) => s.isNotEmpty).join(' — ')),
                  onTap: () => _editSupplier(supplier),
                  trailing: IconButton(
                    tooltip: 'Supprimer',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteSupplier(supplier),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addSupplier, child: const Icon(Icons.add)),
    );
  }
}

class _SupplierFormResult {
  const _SupplierFormResult({required this.name, this.phone, this.address});

  final String name;
  final String? phone;
  final String? address;
}
