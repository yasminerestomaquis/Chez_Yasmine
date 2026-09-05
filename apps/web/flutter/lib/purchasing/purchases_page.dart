import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import 'purchase_form_page.dart';
import 'purchasing_models.dart';
import 'purchasing_repository.dart';
import 'suppliers_page.dart';

class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage> {
  late final PurchasingRepository _repository = PurchasingRepository(ApiClient(), widget.establishmentId);
  late final CatalogRepository _catalog = CatalogRepository(ApiClient(), widget.establishmentId);
  late Future<List<Purchase>> _future = _repository.listPurchases();

  void _reload() => setState(() => _future = _repository.listPurchases());

  Future<void> _openNewPurchase() async {
    final suppliers = await _repository.listSuppliers();
    final products = await _catalog.listProducts();
    if (!mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PurchaseFormPage(repository: _repository, suppliers: suppliers, products: products)),
    );
    if (created == true) _reload();
  }

  Future<void> _receive(Purchase purchase) async {
    try {
      await _repository.receive(purchase.id);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _cancel(Purchase purchase) async {
    try {
      await _repository.cancel(purchase.id);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Achats'),
        actions: [
          IconButton(
            tooltip: 'Fournisseurs',
            icon: const Icon(Icons.local_shipping_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SuppliersPage(repository: _repository))),
          ),
        ],
      ),
      body: FutureBuilder<List<Purchase>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
            return Center(child: Text(message));
          }
          final purchases = snapshot.data!;
          if (purchases.isEmpty) {
            return const Center(child: Text('Aucun achat — créez-en un avec le bouton +'));
          }
          return ListView(
            children: [
              for (final purchase in purchases)
                ListTile(
                  title: Text(purchase.supplier?.name ?? 'Sans fournisseur'),
                  subtitle: Text('${purchase.items.length} article(s) — ${purchase.total.toStringAsFixed(0)} FCFA'),
                  trailing: purchase.status == 'pending'
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(onPressed: () => _cancel(purchase), child: const Text('Annuler')),
                            FilledButton(onPressed: () => _receive(purchase), child: const Text('Recevoir')),
                          ],
                        )
                      : Text(purchaseStatusLabels[purchase.status] ?? purchase.status),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _openNewPurchase, child: const Icon(Icons.add)),
    );
  }
}
