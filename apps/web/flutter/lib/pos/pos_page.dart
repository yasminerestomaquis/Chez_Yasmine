import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import 'payment_dialog.dart';
import 'pos_models.dart';
import 'pos_repository.dart';
import 'receipt_page.dart';

class PosPage extends StatefulWidget {
  const PosPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  late final CatalogRepository _catalog = CatalogRepository(ApiClient(), widget.establishmentId);
  late final PosRepository _pos = PosRepository(ApiClient(), widget.establishmentId);
  late Future<(List<Category>, List<Product>)> _future = _load();

  final List<CartLine> _cart = [];
  String _search = '';
  String? _categoryId;
  bool _isCharging = false;

  Future<(List<Category>, List<Product>)> _load() async {
    final categories = await _catalog.listCategories();
    final products = await _catalog.listProducts();
    return (categories, products);
  }

  double get _subtotal => _cart.fold(0, (sum, line) => sum + line.lineTotal);

  void _addToCart(Product product) {
    setState(() {
      final existing = _cart.where((l) => l.product.id == product.id).firstOrNull;
      if (existing != null) {
        existing.quantity++;
      } else {
        _cart.add(CartLine(product: product, quantity: 1));
      }
    });
  }

  void _changeQuantity(CartLine line, int delta) {
    setState(() {
      line.quantity += delta;
      if (line.quantity <= 0) _cart.remove(line);
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    final total = _subtotal;
    final paymentLines = await showPaymentDialog(context, total: total);
    if (paymentLines == null) return;

    setState(() => _isCharging = true);
    try {
      final sale = await _pos.createSale(
        items: _cart.map((l) => {'productId': l.product.id, 'quantity': l.quantity}).toList(),
        payments: paymentLines.map((p) => {'method': p.method, 'amount': p.amount}).toList(),
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _future = _load();
      });
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReceiptPage(sale: sale)));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isCharging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Caisse')),
      body: FutureBuilder<(List<Category>, List<Product>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
            return Center(child: Text(message));
          }

          final (categories, allProducts) = snapshot.data!;
          final products = allProducts.where((p) {
            final matchesSearch = _search.isEmpty || p.name.toLowerCase().contains(_search.toLowerCase());
            final matchesCategory = _categoryId == null || p.categoryId == _categoryId;
            return matchesSearch && matchesCategory && p.status == 'active';
          }).toList();

          return Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: TextField(
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Rechercher un produit'),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                    ),
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: ChoiceChip(label: const Text('Tous'), selected: _categoryId == null, onSelected: (_) => setState(() => _categoryId = null)),
                          ),
                          for (final category in categories)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: Text(category.name),
                                selected: _categoryId == category.id,
                                onSelected: (_) => setState(() => _categoryId = category.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 160, mainAxisExtent: 110),
                        itemCount: products.length,
                        itemBuilder: (context, index) {
                          final product = products[index];
                          return Card(
                            child: InkWell(
                              onTap: () => _addToCart(product),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                                    const SizedBox(height: 4),
                                    Text('${product.salePrice.toStringAsFixed(0)} FCFA'),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    Expanded(
                      child: _cart.isEmpty
                          ? const Center(child: Text('Panier vide'))
                          : ListView(
                              children: [
                                for (final line in _cart)
                                  ListTile(
                                    title: Text(line.product.name),
                                    subtitle: Text('${line.product.salePrice.toStringAsFixed(0)} FCFA x ${line.quantity}'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => _changeQuantity(line, -1)),
                                        Text('${line.quantity}'),
                                        IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => _changeQuantity(line, 1)),
                                      ],
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
                              const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                              const Spacer(),
                              Text('${_subtotal.toStringAsFixed(0)} FCFA', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _cart.isEmpty || _isCharging ? null : _checkout,
                            child: _isCharging
                                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Encaisser'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
