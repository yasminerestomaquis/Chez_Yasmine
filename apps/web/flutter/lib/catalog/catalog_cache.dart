import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Lets the catalog stay browsable offline (prompt maître §25) : the last
/// successful load is cached locally and served back if a later fetch fails.
/// Photo bytes are NOT stored here (localStorage is capped at ~5 MB): this
/// cache only keeps each product's image ids, so offline the app still knows
/// which photo to look up in `PhotoCache` (IndexedDB, see
/// `product_photo_service.dart`). The service worker never caches photos —
/// it ignores cross-origin requests, and signed URLs change every hour.
class CatalogCache {
  CatalogCache(this.establishmentId);

  final String establishmentId;

  String get _key => 'chez_yasmine_catalog_cache_$establishmentId';

  static Map<String, dynamic> _categoryJson(Category c) => {
        'id': c.id,
        'name': c.name,
        'hasVariablePricing': c.hasVariablePricing,
        'hasCasePricing': c.hasCasePricing,
        'isBeverage': c.isBeverage,
      };

  /// Tout ce dont la saisie hors ligne dépend pour reproduire les règles de
  /// prix du serveur : prix à l'unité, prix de référence variable (Gbêlê),
  /// drapeaux de catégorie. Sans eux, un produit à prix de référence serait
  /// pris pour un produit à prix libre et enverrait un `unitPrice` que le
  /// serveur refuserait à la synchronisation.
  Future<void> save(List<Category> categories, List<Product> products) async {
    final prefs = await SharedPreferences.getInstance();
    final categoryById = {for (final c in categories) c.id: c};
    await prefs.setString(_key, jsonEncode({
      'categories': categories.map(_categoryJson).toList(),
      'products': products.map((p) {
        final category = p.category ?? categoryById[p.categoryId];
        return {
          'id': p.id,
          'name': p.name,
          'categoryId': p.categoryId,
          'category': category == null ? null : _categoryJson(category),
          'salePrice': p.salePrice,
          'unitSalePrice': p.unitSalePrice,
          'requiresPriceAtSale': p.requiresPriceAtSale,
          'referenceSalePrice': p.referenceSalePrice,
          'unit': p.unit,
          'minStock': p.minStock,
          'bottlesPerCase': p.bottlesPerCase,
          'stockQuantity': p.stockQuantity,
          'status': p.status,
          'images': p.images.map((i) => {'id': i.id, 'isPrimary': i.isPrimary, 'position': i.position}).toList(),
        };
      }).toList(),
    }));
  }

  /// Retire du stock mis en cache les quantités d'une vente enregistrée hors
  /// ligne, pour que la Caisse ne montre pas un stock périmé en attendant la
  /// synchronisation. Le prochain chargement réussi du catalogue (stock réel
  /// du serveur) remplace ces valeurs. Le stock peut devenir négatif : la
  /// vente a déjà eu lieu, c'est le serveur qui tranchera.
  Future<void> applyStockDecrements(Map<String, double> quantityByProductId) async {
    if (quantityByProductId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    for (final product in decoded['products'] as List<dynamic>) {
      final map = product as Map<String, dynamic>;
      final used = quantityByProductId[map['id']];
      if (used != null) {
        map['stockQuantity'] = (((map['stockQuantity'] as num).toDouble() - used) * 100).round() / 100;
      }
    }
    await prefs.setString(_key, jsonEncode(decoded));
  }

  Future<(List<Category>, List<Product>)?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final categories = (decoded['categories'] as List<dynamic>)
        .map((e) => Category.fromJson(e as Map<String, dynamic>))
        .toList();
    final products = (decoded['products'] as List<dynamic>)
        .map((e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
    return (categories, products);
  }
}
