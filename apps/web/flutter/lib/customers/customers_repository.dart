import '../api/api_client.dart';
import '../common/read_cache.dart';
import 'customer_models.dart';

/// Correspond à apps/api/nestjs/src/customers/{customers,credits}.controller.ts.
class CustomersRepository {
  CustomersRepository(this._api, this.establishmentId, {ReadCache? cache}) : _cache = cache ?? ReadCache(establishmentId);

  final ApiClient _api;
  final String establishmentId;
  final ReadCache _cache;

  String get _base => '/establishments/$establishmentId/customers';

  Future<List<Customer>> listCustomers() async {
    final json = await _api.get(_base) as List<dynamic>;
    return json.map((e) => Customer.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Liste des clients, avec repli sur la dernière copie locale quand le
  /// serveur est injoignable (consultation hors ligne, voir docs/api/sync.md).
  Future<Cached<List<Customer>>> loadCustomers() {
    return _cache.read(
      name: 'customers',
      fetch: () async => await _api.get(_base) as Object,
      parse: (json) => (json as List<dynamic>).map((e) => Customer.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Future<Customer> createCustomer(String name, {String? phone, String? address, double? creditLimit}) async {
    final json = await _api.post(_base, body: {
      'name': name,
      'phone': ?phone,
      'address': ?address,
      'creditLimit': ?creditLimit,
    }) as Map<String, dynamic>;
    return Customer.fromJson(json);
  }

  Future<List<CreditHistoryEntry>> creditHistory(String customerId) async {
    final json = await _api.get('$_base/$customerId/credit/history') as List<dynamic>;
    return json.map((e) => CreditHistoryEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> recordRepayment(String customerId, double amount) {
    return _api.post('$_base/$customerId/credit/payments', body: {'amount': amount});
  }
}
