class Expense {
  Expense({
    required this.id,
    required this.label,
    this.category,
    required this.amount,
    required this.expenseDate,
    this.note,
  });

  final String id;
  final String label;
  final String? category;
  final double amount;
  final DateTime expenseDate;
  final String? note;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as String,
        label: json['label'] as String,
        category: json['category'] as String?,
        amount: (json['amount'] as num).toDouble(),
        expenseDate: DateTime.parse(json['expenseDate'] as String),
        note: json['note'] as String?,
      );
}
