import '../api/api_client.dart';
import 'purchasing_models.dart';

/// Correspond à apps/api/nestjs/src/purchasing/{suppliers,purchases}.controller.ts.
class PurchasingRepository {
  PurchasingRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId';

  Future<List<Supplier>> listSuppliers() async {
    final json = await _api.get('$_base/suppliers') as List<dynamic>;
    return json.map((e) => Supplier.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Supplier> createSupplier(String name, {String? phone, String? address}) async {
    final json = await _api.post('$_base/suppliers', body: {'name': name, 'phone': ?phone, 'address': ?address})
        as Map<String, dynamic>;
    return Supplier.fromJson(json);
  }

  Future<Supplier> updateSupplier(String supplierId, {String? name, String? phone, String? address}) async {
    final json = await _api.patch('$_base/suppliers/$supplierId', body: {
      'name': ?name,
      'phone': ?phone,
      'address': ?address,
    }) as Map<String, dynamic>;
    return Supplier.fromJson(json);
  }

  Future<void> deleteSupplier(String supplierId) => _api.delete('$_base/suppliers/$supplierId');

  Future<List<Purchase>> listPurchases() async {
    final json = await _api.get('$_base/purchases') as List<dynamic>;
    return json.map((e) => Purchase.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Suggestion de N° de commande (compteur par fournisseur, "Aucun" inclus) — purement indicatif, jamais imposé côté serveur.
  Future<int> nextOrderNumber({String? supplierId}) async {
    final json = await _api.get('$_base/purchases/next-order-number', query: {'supplierId': ?supplierId}) as Map<String, dynamic>;
    return json['orderNumber'] as int;
  }

  Future<Purchase> createPurchase({
    String? id,
    String? supplierId,
    required int orderNumber,
    required DateTime orderDate,
    required List<Map<String, dynamic>> items,
  }) async {
    final json = await _api.post('$_base/purchases', body: {
      'id': ?id,
      'supplierId': ?supplierId,
      'orderNumber': orderNumber,
      'orderDate': _dateOnly(orderDate),
      'items': items,
    }) as Map<String, dynamic>;
    return Purchase.fromJson(json);
  }

  Future<Purchase> updatePurchase(
    String purchaseId, {
    String? supplierId,
    int? orderNumber,
    DateTime? orderDate,
    required List<Map<String, dynamic>> items,
  }) async {
    final json = await _api.patch('$_base/purchases/$purchaseId', body: {
      'supplierId': ?supplierId,
      'orderNumber': ?orderNumber,
      'orderDate': ?(orderDate != null ? _dateOnly(orderDate) : null),
      'items': items,
    }) as Map<String, dynamic>;
    return Purchase.fromJson(json);
  }

  Future<void> deletePurchase(String purchaseId) => _api.delete('$_base/purchases/$purchaseId');

  Future<Purchase> receive(String purchaseId) async {
    final json = await _api.post('$_base/purchases/$purchaseId/receive') as Map<String, dynamic>;
    return Purchase.fromJson(json);
  }

  Future<void> cancel(String purchaseId) {
    return _api.post('$_base/purchases/$purchaseId/cancel');
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
