import '../api/api_client.dart';
import 'models.dart';

/// Traduit les endpoints REST de apps/api/nestjs/src/catalog/ en appels typés.
/// Toutes les routes sont scoped par établissement (convention `:establishmentId`
/// utilisée par PermissionsGuard côté NestJS).
class CatalogRepository {
  CatalogRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId';

  Future<List<Category>> listCategories() async {
    final json = await _api.get('$_base/categories') as List<dynamic>;
    return json.map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Category> createCategory(String name) async {
    final json = await _api.post('$_base/categories', body: {'name': name}) as Map<String, dynamic>;
    return Category.fromJson(json);
  }

  Future<void> deleteCategory(String categoryId) => _api.delete('$_base/categories/$categoryId');

  Future<List<Product>> listProducts() async {
    final json = await _api.get('$_base/products') as List<dynamic>;
    return json.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Product> getProduct(String productId) async {
    final json = await _api.get('$_base/products/$productId') as Map<String, dynamic>;
    return Product.fromJson(json);
  }

  Future<Product> createProduct(Map<String, dynamic> data) async {
    final json = await _api.post('$_base/products', body: data) as Map<String, dynamic>;
    return Product.fromJson(json);
  }

  Future<Product> updateProduct(String productId, Map<String, dynamic> data) async {
    final json = await _api.patch('$_base/products/$productId', body: data) as Map<String, dynamic>;
    return Product.fromJson(json);
  }

  /// Renvoie `true` si le produit a dû être désactivé (`status: 'inactive'`)
  /// plutôt que réellement supprimé — voir `ProductsService.remove` côté API :
  /// un produit référencé par des ventes/achats historiques ne peut pas être
  /// supprimé sans casser cet historique.
  Future<bool> deleteProduct(String productId) async {
    final json = await _api.delete('$_base/products/$productId') as Map<String, dynamic>?;
    return json?['softDeleted'] == true;
  }

  Future<ProductImage> uploadProductImage(String productId, List<int> bytes, String filename, String contentType) async {
    final json = await _api.uploadFile(
      '$_base/products/$productId/images',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
    ) as Map<String, dynamic>;
    return ProductImage.fromJson(json);
  }

  Future<void> deleteProductImage(String productId, String imageId) =>
      _api.delete('$_base/products/$productId/images/$imageId');

  Future<void> setPrimaryImage(String productId, String imageId) =>
      _api.patch('$_base/products/$productId/images/$imageId', body: {'isPrimary': true});

  Future<String> getImageUrl(String productId, String imageId, {String variant = 'medium'}) async {
    final json = await _api.get(
      '$_base/products/$productId/images/$imageId/url',
      query: {'variant': variant},
    ) as Map<String, dynamic>;
    return json['url'] as String;
  }
}
