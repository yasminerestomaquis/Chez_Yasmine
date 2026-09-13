import '../api/api_client.dart';
import 'expense_models.dart';
import 'expense_summary_models.dart';

/// Correspond à apps/api/nestjs/src/expenses/expenses.controller.ts.
class ExpensesRepository {
  ExpensesRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId/expenses';

  Future<List<Expense>> listExpenses() async {
    final json = await _api.get(_base) as List<dynamic>;
    return json
        .map((e) => Expense.fromJson(e as Map<String, dynamic>))
        .toList();
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
    ExpensePaymentMethod paymentMethod = ExpensePaymentMethod.cash,
    ExpenseStatus status = ExpenseStatus.paid,
  }) async {
    final json = await _api.post(
      _base,
      body: {
        'id': ?id,
        'label': label,
        'category': ?category,
        'amount': amount,
        'periodicity': periodicity.value,
        'note': ?note,
        'expenseDate': ?(expenseDate != null ? _dateOnly(expenseDate) : null),
        'marketNumber': ?marketNumber,
        'paymentMethod': paymentMethod.value,
        'status': status.value,
      },
    ) as Map<String, dynamic>;
    return Expense.fromJson(json);
  }

  /// Suggestion éditable pour le prochain N° de marché — jamais imposée côté serveur.
  Future<int> nextMarketNumber() async {
    final json =
        await _api.get('$_base/next-market-number') as Map<String, dynamic>;
    return json['marketNumber'] as int;
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> deleteExpense(String expenseId) {
    return _api.delete('$_base/$expenseId');
  }

  /// Utilisé pour l'action « Annuler » d'une dépense (garde son historique
  /// au lieu de la supprimer) — voir `docs/api/expenses.md`.
  Future<Expense> setExpenseStatus(
    String expenseId,
    ExpenseStatus status,
  ) async {
    final json = await _api.patch(
      '$_base/$expenseId',
      body: {'status': status.value},
    ) as Map<String, dynamic>;
    return Expense.fromJson(json);
  }

  Future<ExpenseSummary> getSummary({
    required String period,
    required int year,
    int? month,
    String? weekOf,
  }) async {
    final json = await _api.get(
      '$_base/summary',
      query: {
        'period': period,
        'year': '$year',
        'month': ?month?.toString(),
        'weekOf': ?weekOf,
      },
    ) as Map<String, dynamic>;
    return ExpenseSummary.fromJson(json);
  }

  Future<ExpenseHistoryPage> listHistory({
    String? period,
    int? year,
    int? month,
    String? weekOf,
    String? category,
    String? status,
    String? paymentMethod,
    int page = 1,
    int pageSize = 8,
  }) async {
    final json = await _api.get(
      '$_base/history',
      query: {
        'period': ?period,
        'year': ?year?.toString(),
        'month': ?month?.toString(),
        'weekOf': ?weekOf,
        'category': ?category,
        'status': ?status,
        'paymentMethod': ?paymentMethod,
        'page': '$page',
        'pageSize': '$pageSize',
      },
    ) as Map<String, dynamic>;
    return ExpenseHistoryPage.fromJson(json);
  }

  Future<({List<int> bytes, String? filename})> exportHistoryExcel({
    String? period,
    int? year,
    int? month,
    String? weekOf,
    String? category,
    String? status,
    String? paymentMethod,
  }) {
    return _api.getBytes(
      '$_base/history.xlsx',
      query: {
        'period': ?period,
        'year': ?year?.toString(),
        'month': ?month?.toString(),
        'weekOf': ?weekOf,
        'category': ?category,
        'status': ?status,
        'paymentMethod': ?paymentMethod,
      },
    );
  }
}
