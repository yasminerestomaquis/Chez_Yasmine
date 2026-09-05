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

  Future<List<Purchase>> listPurchases() async {
    final json = await _api.get('$_base/purchases') as List<dynamic>;
    return json.map((e) => Purchase.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Purchase> createPurchase({String? supplierId, required List<Map<String, dynamic>> items}) async {
    final json = await _api.post('$_base/purchases', body: {'supplierId': ?supplierId, 'items': items}) as Map<String, dynamic>;
    return Purchase.fromJson(json);
  }

  Future<Purchase> receive(String purchaseId) async {
    final json = await _api.post('$_base/purchases/$purchaseId/receive') as Map<String, dynamic>;
    return Purchase.fromJson(json);
  }

  Future<void> cancel(String purchaseId) {
    return _api.post('$_base/purchases/$purchaseId/cancel');
  }
}
