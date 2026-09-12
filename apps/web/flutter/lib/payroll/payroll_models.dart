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
  });
  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String status;
  final List<PayrollLine> lines;

  double get total => lines.fold(0, (sum, l) => sum + l.netAmount);

  factory PayrollRun.fromJson(Map<String, dynamic> json) => PayrollRun(
    id: json['id'] as String,
    periodStart: DateTime.parse(json['periodStart'] as String),
    periodEnd: DateTime.parse(json['periodEnd'] as String),
    status: json['status'] as String,
    lines: (json['lines'] as List<dynamic>)
        .map((e) => PayrollLine.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
