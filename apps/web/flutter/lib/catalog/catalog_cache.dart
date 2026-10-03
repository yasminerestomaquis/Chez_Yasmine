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

  Future<void> save(List<Category> categories, List<Product> products) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode({
      'categories': categories.map((c) => {'id': c.id, 'name': c.name}).toList(),
      'products': products
          .map((p) => {
                'id': p.id,
                'name': p.name,
                'categoryId': p.categoryId,
                'salePrice': p.salePrice,
                'stockQuantity': p.stockQuantity,
                'status': p.status,
                'images': p.images.map((i) => {'id': i.id, 'isPrimary': i.isPrimary, 'position': i.position}).toList(),
              })
          .toList(),
    }));
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
