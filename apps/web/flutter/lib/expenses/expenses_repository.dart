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
  }) async {
    final json = await _api.post(_base, body: {
      'id': ?id,
      'label': label,
      'category': ?category,
      'amount': amount,
      'periodicity': periodicity.value,
      'note': ?note,
    }) as Map<String, dynamic>;
    return Expense.fromJson(json);
  }

  Future<void> deleteExpense(String expenseId) {
    return _api.delete('$_base/$expenseId');
  }
}
