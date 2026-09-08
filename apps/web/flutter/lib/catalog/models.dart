class Category {
  Category({required this.id, required this.name, this.hasVariablePricing = false});

  final String id;
  final String name;

  /// Vrai pour une catégorie sans prix fixe (ex. Poulets, Poissons, Plats
  /// africains) : les produits qui en dépendent n'ont pas de prix d'achat/de
  /// vente dans le catalogue — le prix de vente se saisit en caisse à la
  /// vente, l'achat est suivi via la dépense "Marché" (module Dépenses).
  final bool hasVariablePricing;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String,
        hasVariablePricing: json['hasVariablePricing'] as bool? ?? false,
      );
}

class ProductImage {
  ProductImage({required this.id, required this.isPrimary, required this.position});

  final String id;
  final bool isPrimary;
  final int position;

  factory ProductImage.fromJson(Map<String, dynamic> json) => ProductImage(
        id: json['id'] as String,
        isPrimary: json['isPrimary'] as bool,
        position: json['position'] as int,
      );
}

class Product {
  Product({
    required this.id,
    required this.name,
    required this.status,
    required this.stockQuantity,
    this.salePrice,
    this.categoryId,
    this.category,
    this.description,
    this.reference,
    this.barcode,
    this.unit,
    this.purchasePrice,
    this.vatRate,
    this.minStock,
    this.images = const [],
  });

  final String id;
  final String name;
  final String? categoryId;
  final Category? category;
  final String? description;
  final String? reference;
  final String? barcode;
  final String? unit;
  final double? purchasePrice;
  /// Nul quand `category.hasVariablePricing` est vrai — le prix se saisit
  /// alors en caisse à chaque vente plutôt que d'être fixé dans le catalogue.
  final double? salePrice;
  final double? vatRate;
  final double? minStock;
  final double stockQuantity;
  final String status;
  final List<ProductImage> images;

  bool get hasVariablePricing => category?.hasVariablePricing ?? false;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        name: json['name'] as String,
        categoryId: json['categoryId'] as String?,
        category: json['category'] != null ? Category.fromJson(json['category'] as Map<String, dynamic>) : null,
        description: json['description'] as String?,
        reference: json['reference'] as String?,
        barcode: json['barcode'] as String?,
        unit: json['unit'] as String?,
        purchasePrice: (json['purchasePrice'] as num?)?.toDouble(),
        salePrice: (json['salePrice'] as num?)?.toDouble(),
        vatRate: (json['vatRate'] as num?)?.toDouble(),
        minStock: (json['minStock'] as num?)?.toDouble(),
        stockQuantity: (json['stockQuantity'] as num).toDouble(),
        status: json['status'] as String,
        images: (json['images'] as List<dynamic>? ?? [])
            .map((e) => ProductImage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
