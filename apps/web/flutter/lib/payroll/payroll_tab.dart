import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../common/formatting.dart';
import '../theme/app_theme.dart';
import 'employee_form_dialog.dart';
import 'employee_models.dart';
import 'employees_repository.dart';
import 'payroll_models.dart';
import 'payroll_repository.dart';
import 'payroll_run_page.dart';

/// Sous-onglet Salaires (demande utilisateur du 2026-09-12) : dashboard +
/// liste des employés + accès à la préparation de paie.
class PayrollTab extends StatefulWidget {
  const PayrollTab({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<PayrollTab> createState() => _PayrollTabState();
}

class _PayrollTabState extends State<PayrollTab> {
  late final EmployeesRepository _employees = EmployeesRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final PayrollRepository _payroll = PayrollRepository(
    ApiClient(),
    widget.establishmentId,
  );

  late Future<(PayrollDashboard, List<Employee>)> _future = _load();

  Future<(PayrollDashboard, List<Employee>)> _load() async {
    final now = DateTime.now();
    final results = await (
      _payroll.getDashboard(year: now.year, month: now.month),
      _employees.listEmployees(),
    ).wait;
    return (results.$1, results.$2);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _addEmployee() async {
    final data = await showEmployeeFormDialog(context);
    if (data == null) {
      return;
    }
    try {
      await _employees.createEmployee(
        lastName: data['lastName'] as String,
        firstName: data['firstName'] as String,
        gender: data['gender'] as String?,
        birthDate: data['birthDate'] as DateTime?,
        phone: data['phone'] as String,
        address: (data['address'] as String).isEmpty
            ? null
            : data['address'] as String,
        position: data['position'] as String,
        hireDate: data['hireDate'] as DateTime,
        contractType: data['contractType'] as String?,
        weeklySalary: data['weeklySalary'] as double,
        team: (data['team'] as String).isEmpty ? null : data['team'] as String,
        registrationNumber: (data['registrationNumber'] as String).isEmpty
            ? null
            : data['registrationNumber'] as String,
        notes: (data['notes'] as String).isEmpty
            ? null
            : data['notes'] as String,
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openPayrollRun() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PayrollRunPage(establishmentId: widget.establishmentId),
      ),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(PayrollDashboard, List<Employee>)>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final message = snapshot.error is ApiException
              ? (snapshot.error as ApiException).message
              : '${snapshot.error}';
          return Center(child: Text(message));
        }
        final (dashboard, employees) = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 84,
                ),
                children: [
                  _statCard(
                    "Nombre d'employés",
                    '${dashboard.employeeCount}',
                    AppColors.green,
                  ),
                  _statCard(
                    'Masse salariale (mois)',
                    '${formatAmount(dashboard.massSalariale)} F',
                    AppColors.orange,
                  ),
                  _statCard(
                    'Total payé',
                    '${formatAmount(dashboard.totalPaid)} F',
                    AppColors.green,
                  ),
                  _statCard(
                    'Reste à payer',
                    '${formatAmount(dashboard.remaining)} F',
                    AppColors.alert,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _addEmployee,
                      icon: const Icon(Icons.person_add_alt),
                      label: const Text('Ajouter un employé'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openPayrollRun,
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Préparer la paie'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (employees.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('Aucun employé — ajoutez-en un.')),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final e in employees)
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.greenLight,
                            child: Icon(
                              Icons.person_outline,
                              color: AppColors.green,
                            ),
                          ),
                          title: Text(e.fullName),
                          subtitle: Text('${e.position} — ${e.phone}'),
                          trailing: Text(
                            '${formatAmount(e.weeklySalary)} F/sem.',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
