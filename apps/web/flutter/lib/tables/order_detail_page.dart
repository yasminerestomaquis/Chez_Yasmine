import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../common/formatting.dart';
import '../pos/payment_dialog.dart';
import '../pos/pos_repository.dart';
import '../pos/receipt_page.dart';
import 'tables_models.dart';
import 'tables_repository.dart';

class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({
    super.key,
    required this.repository,
    required this.establishmentId,
    required this.tableId,
  });

  final TablesRepository repository;
  final String establishmentId;
  final String tableId;

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  late final CatalogRepository _catalog = CatalogRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final PosRepository _pos = PosRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late Future<OrderDetail> _future = widget.repository.getOpenOrderForTable(
    widget.tableId,
  );
  bool _isBusy = false;

  void _reload() => setState(
    () => _future = widget.repository.getOpenOrderForTable(widget.tableId),
  );

  Future<void> _addProduct() async {
    final products = await _catalog.listProducts();
    if (!mounted) return;
    final chosen = await showDialog<Product>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Ajouter un produit'),
        children: [
          // Catégorie à prix variable (ex. Poulets/Poissons/Plats africains) :
          // pas encore de saisie de prix ici — à ajouter depuis la Caisse.
          for (final product in products.where(
            (p) => p.status == 'active' && p.salePrice != null,
          ))
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(product),
              child: Text(
                '${product.name} — ${formatAmount(product.salePrice!)} FCFA',
              ),
            ),
        ],
      ),
    );
    if (chosen == null) return;

    setState(() => _isBusy = true);
    try {
      final order = await _future;
      await widget.repository.addItem(
        order.id,
        productId: chosen.id,
        quantity: 1,
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _removeItem(OrderDetail order, OrderItemDetail item) async {
    setState(() => _isBusy = true);
    try {
      await widget.repository.removeItem(order.id, item.id);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _checkout(OrderDetail order) async {
    if (order.items.isEmpty) return;
    final outcome = await showPaymentDialog(context, total: order.total);
    if (outcome == null) return;

    setState(() => _isBusy = true);
    try {
      final sale = await _pos.createSale(
        items: order.items
            .map((i) => {'productId': i.productId, 'quantity': i.quantity})
            .toList(),
        payments: outcome.lines
            .map((p) => {'method': p.method, 'amount': p.amount})
            .toList(),
        orderId: order.id,
        tableId: widget.tableId,
        source: 'table',
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ReceiptPage(sale: sale)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Addition')),
      body: FutureBuilder<OrderDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException
                ? (snapshot.error as ApiException).message
                : '${snapshot.error}';
            return Center(child: Text(message));
          }

          final order = snapshot.data!;
          return Column(
            children: [
              Expanded(
                child: order.items.isEmpty
                    ? const Center(
                        child: Text(
                          'Aucun article — ajoutez-en un avec le bouton +',
                        ),
                      )
                    : ListView(
                        children: [
                          for (final item in order.items)
                            ListTile(
                              title: Text(item.productName),
                              subtitle: Text(
                                '${formatAmount(item.unitPrice)} FCFA x ${item.quantity.toStringAsFixed(0)}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: _isBusy
                                    ? null
                                    : () => _removeItem(order, item),
                              ),
                            ),
                        ],
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Total',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${formatAmount(order.total)} FCFA',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _isBusy || order.items.isEmpty
                          ? null
                          : () => _checkout(order),
                      child: const Text('Encaisser'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isBusy ? null : _addProduct,
        child: const Icon(Icons.add),
      ),
    );
  }
}
