class PayrollDashboard {
  PayrollDashboard({
    required this.employeeCount,
    required this.massSalariale,
    required this.totalPaid,
    required this.remaining,
  });
  final int employeeCount;
  final double massSalariale;
  final double totalPaid;
  final double remaining;

  factory PayrollDashboard.fromJson(Map<String, dynamic> json) =>
      PayrollDashboard(
        employeeCount: json['employeeCount'] as int,
        massSalariale: (json['massSalariale'] as num).toDouble(),
        totalPaid: (json['totalPaid'] as num).toDouble(),
        remaining: (json['remaining'] as num).toDouble(),
      );
}

class PayrollLine {
  PayrollLine({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.baseSalary,
    required this.advance,
    required this.adjustment,
    required this.netAmount,
  });
  final String id;
  final String employeeId;
  final String employeeName;
  final double baseSalary;
  final double advance;
  final double adjustment;
  final double netAmount;

  factory PayrollLine.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'] as Map<String, dynamic>;
    return PayrollLine(
      id: json['id'] as String,
      employeeId: json['employeeId'] as String,
      employeeName: '${employee['lastName']} ${employee['firstName']}',
      baseSalary: (json['baseSalary'] as num).toDouble(),
      advance: (json['advance'] as num).toDouble(),
      adjustment: (json['adjustment'] as num).toDouble(),
      netAmount: (json['netAmount'] as num).toDouble(),
    );
  }
}

/// 'prepared' | 'validated' | 'paid' | 'cancelled'.
class PayrollRun {
  PayrollRun({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    required this.lines,
    this.createdAt,
    this.paidAt,
    this.expenseDate,
  });
  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String status;
  final List<PayrollLine> lines;

  /// Préparation de la paie / paiement effectif / date de la dépense
  /// « Salaires » générée au paiement (nulle tant que la paie n'est pas payée).
  final DateTime? createdAt;
  final DateTime? paidAt;
  final DateTime? expenseDate;

  double get total => lines.fold(0, (sum, l) => sum + l.netAmount);

  static DateTime? _optionalDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  factory PayrollRun.fromJson(Map<String, dynamic> json) => PayrollRun(
    id: json['id'] as String,
    periodStart: DateTime.parse(json['periodStart'] as String),
    periodEnd: DateTime.parse(json['periodEnd'] as String),
    status: json['status'] as String,
    lines: (json['lines'] as List<dynamic>)
        .map((e) => PayrollLine.fromJson(e as Map<String, dynamic>))
        .toList(),
    createdAt: _optionalDate(json['createdAt']),
    paidAt: _optionalDate(json['paidAt']),
    expenseDate: _optionalDate(
      (json['expense'] as Map<String, dynamic>?)?['expenseDate'],
    ),
  );
}
