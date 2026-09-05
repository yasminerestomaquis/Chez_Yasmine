class Category {
  Category({required this.id, required this.name});

  final String id;
  final String name;

  factory Category.fromJson(Map<String, dynamic> json) => Category(id: json['id'] as String, name: json['name'] as String);
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
    required this.salePrice,
    required this.status,
    required this.stockQuantity,
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
  final double salePrice;
  final double? vatRate;
  final double? minStock;
  final double stockQuantity;
  final String status;
  final List<ProductImage> images;

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
        salePrice: (json['salePrice'] as num).toDouble(),
        vatRate: (json['vatRate'] as num?)?.toDouble(),
        minStock: (json['minStock'] as num?)?.toDouble(),
        stockQuantity: (json['stockQuantity'] as num).toDouble(),
        status: json['status'] as String,
        images: (json['images'] as List<dynamic>? ?? [])
            .map((e) => ProductImage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
