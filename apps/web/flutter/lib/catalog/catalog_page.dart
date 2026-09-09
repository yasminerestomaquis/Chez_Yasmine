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
  late Future<void> _future;
  List<Category> _categories = [];
  List<Product> _products = [];
  Category? _selectedCategory;
  bool _showUncategorized = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _load() async {
    final categories = await _repository.listCategories();
    final products = await _repository.listProducts();
    _categories = categories;
    _products = products;
  }

  void _reload() => setState(() => _future = _load());

  List<String> _categoryBadges(Category category) => [
        if (category.hasVariablePricing) 'Prix variable',
        if (category.hasCasePricing) 'Prix par casier',
      ];

  Future<void> _addCategory() async {
    final result = await _showCategoryDialog(title: 'Nouvelle catégorie');
    if (result == null) return;
    try {
      await _repository.createCategory(
        result.name,
        hasVariablePricing: result.hasVariablePricing,
        hasCasePricing: result.hasCasePricing,
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _editCategory(BuildContext dialogContext, Category category, StateSetter setDialogState) async {
    final result = await _showCategoryDialog(
      title: 'Modifier la catégorie',
      initialName: category.name,
      initialHasVariablePricing: category.hasVariablePricing,
      initialHasCasePricing: category.hasCasePricing,
    );
    if (result == null) return;
    try {
      final updated = await _repository.updateCategory(
        category.id,
        name: result.name,
        hasVariablePricing: result.hasVariablePricing,
        hasCasePricing: result.hasCasePricing,
      );
      _categories = [for (final c in _categories) if (c.id == category.id) updated else c];
      setDialogState(() {});
      _reload();
    } on ApiException catch (e) {
      if (!dialogContext.mounted) return;
      ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<_CategoryFormResult?> _showCategoryDialog({
    required String title,
    String? initialName,
    bool initialHasVariablePricing = false,
    bool initialHasCasePricing = false,
  }) {
    final controller = TextEditingController(text: initialName ?? '');
    var hasVariablePricing = initialHasVariablePricing;
    var hasCasePricing = initialHasCasePricing;
    return showDialog<_CategoryFormResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Nom')),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: hasVariablePricing,
                onChanged: (v) => setState(() => hasVariablePricing = v ?? false),
                title: const Text('Prix variable'),
                subtitle: const Text('Pas de prix fixe : saisi en caisse à chaque vente (ex. Poulets, Poissons, Plats africains).'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: hasCasePricing,
                onChanged: (v) => setState(() => hasCasePricing = v ?? false),
                title: const Text('Prix par casier'),
                subtitle: const Text('Vendu par casier (ex. Bières, Vins, Sucreries) : active Nbre de bouteilles/Prix d\'achat par casier.'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                Navigator.of(context).pop(_CategoryFormResult(
                  name: name,
                  hasVariablePricing: hasVariablePricing,
                  hasCasePricing: hasCasePricing,
                ));
              },
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProductForm({required List<Category> categories, Product? existing, String? initialCategoryId}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductFormPage(
          repository: _repository,
          categories: categories,
          existing: existing,
          initialCategoryId: initialCategoryId,
        ),
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce produit ?'),
        content: Text('« ${product.name} » sera retiré du catalogue.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final softDeleted = await _repository.deleteProduct(product.id);
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            softDeleted
                ? '« ${product.name} » a des ventes/achats existants : il a été désactivé plutôt que supprimé.'
                : '« ${product.name} » a été supprimé.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteCategory(BuildContext dialogContext, Category category, StateSetter setDialogState) async {
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette catégorie ?'),
        content: Text('« ${category.name} » sera supprimée ; les produits qui y étaient rattachés deviennent sans catégorie.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.deleteCategory(category.id);
      _categories = _categories.where((c) => c.id != category.id).toList();
      setDialogState(() {});
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _manageCategories() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Catégories'),
            content: SizedBox(
              width: 360,
              child: _categories.isEmpty
                  ? const Text('Aucune catégorie.')
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final category in _categories)
                          ListTile(
                            title: Text(category.name),
                            subtitle: _categoryBadges(category).isEmpty ? null : Text(_categoryBadges(category).join(' · ')),
                            onTap: () => _editCategory(dialogContext, category, setDialogState),
                            trailing: IconButton(
                              tooltip: 'Supprimer',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteCategory(dialogContext, category, setDialogState),
                            ),
                          ),
                      ],
                    ),
            ),
            actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Fermer'))],
          );
        },
      ),
    );
  }

  bool get _inCategoryView => _selectedCategory != null || _showUncategorized;

  void _openCategory(Category? category, {bool uncategorized = false}) {
    setState(() {
      _selectedCategory = category;
      _showUncategorized = uncategorized;
    });
  }

  void _backToCategories() => setState(() {
        _selectedCategory = null;
        _showUncategorized = false;
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _inCategoryView ? BackButton(onPressed: _backToCategories) : null,
        title: Text(_selectedCategory?.name ?? (_showUncategorized ? 'Sans catégorie' : 'Catalogue')),
        actions: [
          IconButton(onPressed: _manageCategories, icon: const Icon(Icons.category_outlined), tooltip: 'Gérer les catégories'),
          IconButton(onPressed: _addCategory, icon: const Icon(Icons.add), tooltip: 'Nouvelle catégorie'),
        ],
      ),
      body: FutureBuilder<void>(
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

          if (_products.isEmpty && _categories.isEmpty) {
            return const Center(child: Text('Aucun produit — ajoutez-en un avec le bouton +'));
          }

          if (!_inCategoryView) {
            return _buildCategoryGrid();
          }

          final products = _selectedCategory != null
              ? _products.where((p) => p.categoryId == _selectedCategory!.id).toList()
              : _products.where((p) => p.categoryId == null).toList();

          if (products.isEmpty) {
            return const Center(child: Text('Aucun produit dans cette catégorie — ajoutez-en un avec le bouton +'));
          }

          return _buildProductGrid(products);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openProductForm(categories: _categories, initialCategoryId: _selectedCategory?.id),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    final uncategorizedCount = _products.where((p) => p.categoryId == null).length;
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisExtent: 100),
      itemCount: _categories.length + (uncategorizedCount > 0 ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < _categories.length) {
          final category = _categories[index];
          final count = _products.where((p) => p.categoryId == category.id).length;
          return _CategoryTile(
            name: category.name,
            count: count,
            badges: _categoryBadges(category),
            onTap: () => _openCategory(category),
          );
        }
        return _CategoryTile(
          name: 'Sans catégorie',
          count: uncategorizedCount,
          badges: const [],
          onTap: () => _openCategory(null, uncategorized: true),
        );
      },
    );
  }

  Widget _buildProductGrid(List<Product> products) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisExtent: 240),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return _ProductCard(
          product: product,
          repository: _repository,
          onTap: () => _openProductForm(categories: _categories, existing: product),
          onDelete: () => _deleteProduct(product),
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.name, required this.count, required this.badges, required this.onTap});

  final String name;
  final int count;
  final List<String> badges;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 4),
              Text('$count produit${count > 1 ? 's' : ''}'),
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(badges.join(' · '), style: const TextStyle(fontStyle: FontStyle.italic)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryFormResult {
  const _CategoryFormResult({required this.name, required this.hasVariablePricing, required this.hasCasePricing});

  final String name;
  final bool hasVariablePricing;
  final bool hasCasePricing;
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.repository, required this.onTap, required this.onDelete});

  final Product product;
  final CatalogRepository repository;
  final VoidCallback onTap;
  final VoidCallback onDelete;

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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  primaryImage == null
                      ? const ColoredBox(color: Color(0x11000000), child: Icon(Icons.local_drink_outlined, size: 40))
                      : FutureBuilder<String>(
                          future: repository.getImageUrl(product.id, primaryImage.id, variant: 'small'),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const ColoredBox(color: Color(0x11000000));
                            return ColoredBox(
                              color: const Color(0x11000000),
                              child: Image.network(snapshot.data!, fit: BoxFit.contain),
                            );
                          },
                        ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      tooltip: 'Supprimer',
                      icon: const Icon(Icons.delete_outline),
                      style: IconButton.styleFrom(backgroundColor: Colors.white70),
                      onPressed: onDelete,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(product.salePrice != null ? '${product.salePrice!.toStringAsFixed(0)} FCFA' : 'Prix variable'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
