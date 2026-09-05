import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'catalog_repository.dart';
import 'models.dart';
import 'product_form_page.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late final CatalogRepository _repository = CatalogRepository(ApiClient(), widget.establishmentId);
  late Future<(List<Category>, List<Product>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Category>, List<Product>)> _load() async {
    final categories = await _repository.listCategories();
    final products = await _repository.listProducts();
    return (categories, products);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nouvelle catégorie'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Nom')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Créer')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await _repository.createCategory(name);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openProductForm({required List<Category> categories, Product? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductFormPage(repository: _repository, categories: categories, existing: existing),
      ),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catalogue'),
        actions: [IconButton(onPressed: _addCategory, icon: const Icon(Icons.category_outlined), tooltip: 'Nouvelle catégorie')],
      ),
      body: FutureBuilder<(List<Category>, List<Product>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 40),
                    const SizedBox(height: 12),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _reload, child: const Text('Réessayer')),
                  ],
                ),
              ),
            );
          }

          final (categories, products) = snapshot.data!;
          if (products.isEmpty) {
            return const Center(child: Text('Aucun produit — ajoutez-en un avec le bouton +'));
          }

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisExtent: 220),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return _ProductCard(
                product: product,
                repository: _repository,
                onTap: () => _openProductForm(categories: categories, existing: product),
              );
            },
          );
        },
      ),
      floatingActionButton: FutureBuilder<(List<Category>, List<Product>)>(
        future: _future,
        builder: (context, snapshot) {
          final categories = snapshot.data?.$1 ?? const <Category>[];
          return FloatingActionButton(
            onPressed: () => _openProductForm(categories: categories),
            child: const Icon(Icons.add),
          );
        },
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.repository, required this.onTap});

  final Product product;
  final CatalogRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primaryImage = product.images.where((i) => i.isPrimary).firstOrNull ?? product.images.firstOrNull;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: primaryImage == null
                  ? const ColoredBox(color: Color(0x11000000), child: Icon(Icons.local_drink_outlined, size: 40))
                  : FutureBuilder<String>(
                      future: repository.getImageUrl(product.id, primaryImage.id, variant: 'small'),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const ColoredBox(color: Color(0x11000000));
                        return Image.network(snapshot.data!, fit: BoxFit.cover);
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${product.salePrice.toStringAsFixed(0)} FCFA'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
