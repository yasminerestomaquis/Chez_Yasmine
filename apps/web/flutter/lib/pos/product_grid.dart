import 'package:flutter/material.dart';

import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../common/formatting.dart';
import '../theme/app_theme.dart';

/// Grille de produits (recherche + filtre catégorie + grille avec photos) —
/// extraite de `PosPage` pour être réutilisée telle quelle par l'écran de
/// table (`table_order_page.dart`). Ne connaît rien du panier appelant, juste
/// `quantityInCart`/`onProductTap`.
class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required this.repository,
    required this.categories,
    required this.products,
    required this.search,
    required this.categoryId,
    required this.quantityInCart,
    required this.onSearchChanged,
    required this.onCategoryChanged,
    required this.onProductTap,
    required this.crossAxisExtent,
  });

  final CatalogRepository repository;
  final List<Category> categories;
  final List<Product> products;
  final String search;
  final String? categoryId;
  final int Function(String productId) quantityInCart;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<Product> onProductTap;
  final double crossAxisExtent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Rechercher un produit',
              isDense: true,
            ),
            onChanged: onSearchChanged,
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: const Text('Tous'),
                  selected: categoryId == null,
                  onSelected: (_) => onCategoryChanged(null),
                ),
              ),
              for (final category in categories)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(category.name),
                    selected: categoryId == category.id,
                    onSelected: (_) => onCategoryChanged(category.id),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: crossAxisExtent,
              mainAxisExtent: 132,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return PosProductTile(
                product: product,
                repository: repository,
                quantityInCart: quantityInCart(product.id),
                onTap: () => onProductTap(product),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Barre flottante « N articles · total FCFA » affichée en mobile quand le
/// panier n'est pas vide — tap ouvre le panneau panier en feuille modale.
class FloatingCartBar extends StatelessWidget {
  const FloatingCartBar({
    super.key,
    required this.itemCount,
    required this.total,
    required this.onTap,
  });

  final int itemCount;
  final double total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Material(
          color: AppColors.green,
          borderRadius: BorderRadius.circular(14),
          elevation: 3,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(
                    Icons.shopping_cart,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$itemCount article${itemCount > 1 ? 's' : ''} · ${formatAmount(total)} FCFA',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Voir le panier',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PosProductTile extends StatelessWidget {
  const PosProductTile({
    super.key,
    required this.product,
    required this.repository,
    required this.quantityInCart,
    required this.onTap,
  });

  final Product product;
  final CatalogRepository repository;
  final int quantityInCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primaryImage =
        product.images.where((i) => i.isPrimary).firstOrNull ??
        product.images.firstOrNull;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: primaryImage == null
                      ? const ColoredBox(
                          color: AppColors.greenLight,
                          child: Icon(
                            Icons.local_drink_outlined,
                            size: 26,
                            color: AppColors.green,
                          ),
                        )
                      : FutureBuilder<String>(
                          future: repository.getImageUrl(
                            product.id,
                            primaryImage.id,
                            variant: 'thumbnail',
                          ),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const ColoredBox(
                                color: AppColors.greenLight,
                              );
                            }
                            return ColoredBox(
                              color: AppColors.greenLight,
                              child: Image.network(
                                snapshot.data!,
                                fit: BoxFit.contain,
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text(
                        product.salePrice != null
                            ? '${formatAmount(product.salePrice!)} FCFA'
                            : 'Prix variable',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (quantityInCart > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$quantityInCart',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
