import '../api/api_client.dart';
import 'expense_models.dart';

/// Correspond à apps/api/nestjs/src/expenses/expenses.controller.ts.
class ExpensesRepository {
  ExpensesRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId/expenses';

  Future<List<Expense>> listExpenses() async {
    final json = await _api.get(_base) as List<dynamic>;
    return json.map((e) => Expense.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Expense> createExpense({
    String? id,
    required String label,
    String? category,
    required double amount,
    ExpensePeriodicity periodicity = ExpensePeriodicity.oneOff,
    String? note,
    DateTime? expenseDate,
    int? marketNumber,
  }) async {
    final json = await _api.post(_base, body: {
      'id': ?id,
      'label': label,
      'category': ?category,
      'amount': amount,
      'periodicity': periodicity.value,
      'note': ?note,
      'expenseDate': ?(expenseDate != null ? _dateOnly(expenseDate) : null),
      'marketNumber': ?marketNumber,
    }) as Map<String, dynamic>;
    return Expense.fromJson(json);
  }

  /// Suggestion éditable pour le prochain N° de marché — jamais imposée côté serveur.
  Future<int> nextMarketNumber() async {
    final json = await _api.get('$_base/next-market-number') as Map<String, dynamic>;
    return json['marketNumber'] as int;
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> deleteExpense(String expenseId) {
    return _api.delete('$_base/$expenseId');
  }
}
