import 'expense_models.dart';

class ExpenseCategoryAmount {
  ExpenseCategoryAmount({required this.category, required this.amount});
  final String category;
  final double amount;

  factory ExpenseCategoryAmount.fromJson(Map<String, dynamic> json) =>
      ExpenseCategoryAmount(
        category: json['category'] as String,
        amount: (json['amount'] as num).toDouble(),
      );
}

class ExpenseSummary {
  ExpenseSummary({
    required this.from,
    required this.to,
    required this.totalAmount,
    required this.totalSalaries,
    required this.totalMarket,
    required this.totalFixedCharges,
    required this.previousTotalAmount,
    this.changePercent,
    this.changePercentSalaries,
    this.changePercentMarket,
    this.changePercentFixedCharges,
    required this.byCategory,
    required this.recent,
  });

  final DateTime from;
  final DateTime to;
  final double totalAmount;
  final double totalSalaries;
  final double totalMarket;
  final double totalFixedCharges;
  final double previousTotalAmount;
  final double? changePercent;
  final double? changePercentSalaries;
  final double? changePercentMarket;
  final double? changePercentFixedCharges;
  final List<ExpenseCategoryAmount> byCategory;
  final List<Expense> recent;

  factory ExpenseSummary.fromJson(Map<String, dynamic> json) => ExpenseSummary(
    from: DateTime.parse(json['from'] as String),
    to: DateTime.parse(json['to'] as String),
    totalAmount: (json['totalAmount'] as num).toDouble(),
    totalSalaries: (json['totalSalaries'] as num).toDouble(),
    totalMarket: (json['totalMarket'] as num).toDouble(),
    totalFixedCharges: (json['totalFixedCharges'] as num).toDouble(),
    previousTotalAmount: (json['previousTotalAmount'] as num).toDouble(),
    changePercent: (json['changePercent'] as num?)?.toDouble(),
    changePercentSalaries: (json['changePercentSalaries'] as num?)?.toDouble(),
    changePercentMarket: (json['changePercentMarket'] as num?)?.toDouble(),
    changePercentFixedCharges: (json['changePercentFixedCharges'] as num?)
        ?.toDouble(),
    byCategory: (json['byCategory'] as List<dynamic>)
        .map((e) => ExpenseCategoryAmount.fromJson(e as Map<String, dynamic>))
        .toList(),
    recent: (json['recent'] as List<dynamic>)
        .map((e) => Expense.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class ExpenseHistoryPage {
  ExpenseHistoryPage({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });
  final List<Expense> items;
  final int total;
  final int page;
  final int pageSize;

  factory ExpenseHistoryPage.fromJson(Map<String, dynamic> json) =>
      ExpenseHistoryPage(
        items: (json['items'] as List<dynamic>)
            .map((e) => Expense.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: json['total'] as int,
        page: json['page'] as int,
        pageSize: json['pageSize'] as int,
      );
}
