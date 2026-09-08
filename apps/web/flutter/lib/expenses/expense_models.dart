/// Liste prédéfinie de natures de dépenses (suggestions), volontairement
/// NON fermée : l'utilisateur peut toujours saisir une catégorie différente
/// via l'option « Autre » du formulaire — voir `ExpenseCategoryField`.
const List<String> kPredefinedExpenseCategories = [
  'Loyer',
  'Salaires',
  'Cie',
  'Eau',
  'Patentes',
  'Entretien',
  'Bouteilles de gaz',
  'Charbon',
  // Achat journalier (marché) des produits à prix variable du Catalogue
  // (ex. Poulets, Poissons, Plats africains) — voir docs/api/catalog.md.
  'Marché',
];

/// 'one_off' | 'recurring' — étiquette informative uniquement (voir
/// apps/api/nestjs/src/expenses/dto/expense.dto.ts) : ne change rien au
/// calcul du bénéfice net, pas de génération automatique de dépense.
enum ExpensePeriodicity {
  oneOff('one_off', 'Ponctuelle'),
  recurring('recurring', 'Récurrente');

  const ExpensePeriodicity(this.value, this.label);

  final String value;
  final String label;

  static ExpensePeriodicity fromValue(String? value) =>
      ExpensePeriodicity.values.firstWhere((p) => p.value == value, orElse: () => ExpensePeriodicity.oneOff);
}

class Expense {
  Expense({
    required this.id,
    required this.label,
    this.category,
    required this.amount,
    required this.expenseDate,
    this.periodicity = ExpensePeriodicity.oneOff,
    this.note,
  });

  final String id;
  final String label;
  final String? category;
  final double amount;
  final DateTime expenseDate;
  final ExpensePeriodicity periodicity;
  final String? note;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as String,
        label: json['label'] as String,
        category: json['category'] as String?,
        amount: (json['amount'] as num).toDouble(),
        expenseDate: DateTime.parse(json['expenseDate'] as String),
        periodicity: ExpensePeriodicity.fromValue(json['periodicity'] as String?),
        note: json['note'] as String?,
      );
}
