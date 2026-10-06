import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../common/formatting.dart';
import 'employee_models.dart';
import 'employees_repository.dart';
import 'payroll_dialogs.dart';
import 'payroll_models.dart';
import 'payroll_repository.dart';
import 'payroll_run_widgets.dart';

DateTime _mondayOf(DateTime date) {
  final weekdayIndex = (date.weekday - 1) % 7;
  return DateTime(
    date.year,
    date.month,
    date.day,
  ).subtract(Duration(days: weekdayIndex));
}

enum _PrepareChoice { currentWeek, otherWeek, month }

/// Workflow préparé → validé → payé → annulé (demande utilisateur du
/// 2026-09-12). Le paiement crée automatiquement, côté serveur, une dépense
/// "Salaires" — voir PayrollService.pay.
class PayrollRunPage extends StatefulWidget {
  const PayrollRunPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<PayrollRunPage> createState() => _PayrollRunPageState();
}

class _PayrollRunPageState extends State<PayrollRunPage> {
  late final PayrollRepository _repository = PayrollRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final EmployeesRepository _employees = EmployeesRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late Future<List<PayrollRun>> _future = _repository.listRuns();
  bool _isBusy = false;

  Future<void> _reload() async {
    final future = _repository.listRuns();
    setState(() {
      _future = future;
    });
    await future;
  }

  /// Propose les trois paies préparables : semaine en cours, semaine omise
  /// (n'importe quelle semaine passée) et paie mensuelle (employés payés au
  /// mois), puis lance la préparation.
  Future<void> _choosePrepare() async {
    if (_isBusy) return;
    final choice = await showDialog<_PrepareChoice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Préparer une paie'),
        children: [
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(_PrepareChoice.currentWeek),
            child: const ListTile(
              leading: Icon(Icons.today_outlined),
              title: Text('Semaine en cours'),
              subtitle: Text('Employés payés à la semaine'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () =>
                Navigator.of(context).pop(_PrepareChoice.otherWeek),
            child: const ListTile(
              leading: Icon(Icons.history_toggle_off),
              title: Text('Une autre semaine (semaine omise)'),
              subtitle: Text('Choisir un jour de la semaine à préparer'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(_PrepareChoice.month),
            child: const ListTile(
              leading: Icon(Icons.calendar_month_outlined),
              title: Text('Paie mensuelle'),
              subtitle: Text(
                'Employés payés au mois — choisir un jour du mois',
              ),
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    DateTime start;
    DateTime end;
    var type = 'weekly';
    if (choice == _PrepareChoice.currentWeek) {
      start = _mondayOf(DateTime.now());
      end = start.add(const Duration(days: 6));
    } else {
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
        helpText: choice == _PrepareChoice.otherWeek
            ? 'Un jour de la semaine à préparer'
            : 'Un jour du mois à payer',
      );
      if (picked == null || !mounted) return;
      if (choice == _PrepareChoice.otherWeek) {
        start = _mondayOf(picked);
        end = start.add(const Duration(days: 6));
      } else {
        type = 'monthly';
        start = DateTime(picked.year, picked.month, 1);
        end = DateTime(picked.year, picked.month + 1, 0);
      }
      final fmt = DateFormat('dd/MM/yyyy');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Préparer cette paie ?'),
          content: Text(
            '${type == 'monthly' ? 'Paie mensuelle' : 'Paie hebdomadaire'} du '
            '${fmt.format(start)} au ${fmt.format(end)}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Préparer'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    // Une seule paie non annulée par type et par début de période (le serveur
    // le refuse aussi) : on évite l'aller-retour réseau et on explique.
    final runs = await _future.catchError((_) => <PayrollRun>[]);
    if (_alreadyPrepared(runs, start, type)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Une paie existe déjà pour cette période.'),
        ),
      );
      return;
    }
    await _prepare(start, end, type);
  }

  Future<void> _prepare(DateTime start, DateTime end, String type) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await _repository.prepare(
        periodStart: start,
        periodEnd: end,
        periodType: type,
      );
      // `await` ici (pas de fire-and-forget) : la liste rechargée est affichée
      // AVANT de réactiver le bouton, fermant la fenêtre où un second appui
      // créerait un doublon.
      await _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _editLine(PayrollRun run, PayrollLine line) async {
    final values = await showPayrollLineDialog(context, line);
    if (values == null) return;
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await _repository.updateLine(
        run.id,
        line.id,
        advance: values.advance,
        adjustment: values.adjustment,
      );
      await _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Ajoute à la paie un employé actif qui n'y figure pas encore.
  Future<void> _addEmployee(PayrollRun run) async {
    if (_isBusy) return;
    List<Employee> employees;
    try {
      employees = await _employees.listEmployees();
    } on ApiException catch (e) {
      _showMessage(e.message);
      return;
    }
    if (!mounted) return;
    final onRun = run.lines.map((l) => l.employeeId).toSet();
    final employee = await showAddPayrollEmployeeDialog(
      context,
      employees
          .where(
            (e) =>
                e.isActive &&
                e.salaryType == run.periodType &&
                !onRun.contains(e.id),
          )
          .toList(),
      paid: run.status == 'paid',
      monthly: run.isMonthly,
    );
    if (employee == null || _isBusy) return;
    setState(() => _isBusy = true);
    try {
      await _repository.addLine(run.id, employee.id);
      await _reload();
    } on ApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _removeLine(PayrollRun run, PayrollLine line) async {
    final confirmed = await confirmRemovePayrollLine(
      context,
      line,
      paid: run.status == 'paid',
    );
    if (!confirmed || _isBusy) return;
    setState(() => _isBusy = true);
    try {
      await _repository.removeLine(run.id, line.id);
      await _reload();
    } on ApiException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _editPeriod(PayrollRun run) async {
    final period = await showPayrollPeriodDialog(context, run);
    if (period == null) return;
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await _repository.updateRun(
        run.id,
        periodStart: period.start,
        periodEnd: period.end,
      );
      await _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _validate(PayrollRun run) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await _repository.validate(run.id);
      await _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _pay(PayrollRun run) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer le paiement'),
        content: Text(
          'Payer ${formatAmount(run.total)} FCFA pour ${run.lines.length} employé(s) ? '
          'Une dépense "Salaires" sera créée automatiquement et cette action ne pourra plus être annulée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Payer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await _repository.pay(run.id);
      await _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _cancel(PayrollRun run) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await _repository.cancel(run.id);
      await _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Vrai si une paie non annulée du même type commence déjà ce jour-là
  /// (comparaison par jour calendaire : `periodStart` est une date sans heure).
  bool _alreadyPrepared(List<PayrollRun> runs, DateTime start, String type) {
    return runs.any(
      (r) =>
          r.status != 'cancelled' &&
          r.periodType == type &&
          r.periodStart.year == start.year &&
          r.periodStart.month == start.month &&
          r.periodStart.day == start.day,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Préparer la paie')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBusy ? null : _choosePrepare,
        icon: const Icon(Icons.add),
        label: const Text('Préparer une paie'),
      ),
      body: FutureBuilder<List<PayrollRun>>(
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
          final runs = snapshot.data!;
          if (runs.isEmpty) {
            return const Center(
              child: Text(
                'Aucune paie préparée — utilisez le bouton "Préparer".',
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final run in runs)
                PayrollRunCardFrame(
                  run: run,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: PayrollRunTitle(run)),
                          if (run.status == 'prepared' ||
                              run.status == 'validated')
                            IconButton(
                              tooltip: 'Modifier la période',
                              icon: const Icon(Icons.edit_calendar_outlined),
                              onPressed: _isBusy
                                  ? null
                                  : () => _editPeriod(run),
                            ),
                          PayrollStatusChip(run.status),
                        ],
                      ),
                      for (final line in run.lines)
                        ListTile(
                          dense: true,
                          title: Text(line.employeeName),
                          subtitle: Text(
                            'Base ${formatAmount(line.baseSalary)} — Avance ${formatAmount(line.advance)} — Ajust. ${formatAmount(line.adjustment)}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${formatAmount(line.netAmount)} F',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (isPayrollRunEditable(run))
                                IconButton(
                                  tooltip: 'Retirer de la paie',
                                  icon: const Icon(
                                    Icons.person_remove_outlined,
                                  ),
                                  onPressed: _isBusy
                                      ? null
                                      : () => _removeLine(run, line),
                                ),
                            ],
                          ),
                          onTap:
                              (run.status != 'cancelled' &&
                                  run.status != 'paid' &&
                                  !_isBusy)
                              ? () => _editLine(run, line)
                              : null,
                        ),
                      if (isPayrollRunEditable(run))
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _isBusy ? null : () => _addEmployee(run),
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('Ajouter un employé'),
                          ),
                        ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total : ${formatAmount(run.total)} FCFA',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Row(
                            children: [
                              if (run.status == 'prepared') ...[
                                TextButton(
                                  onPressed: _isBusy
                                      ? null
                                      : () => _cancel(run),
                                  child: const Text('Annuler'),
                                ),
                                FilledButton(
                                  onPressed: _isBusy
                                      ? null
                                      : () => _validate(run),
                                  child: const Text('Valider'),
                                ),
                              ],
                              if (run.status == 'validated') ...[
                                TextButton(
                                  onPressed: _isBusy
                                      ? null
                                      : () => _cancel(run),
                                  child: const Text('Annuler'),
                                ),
                                FilledButton(
                                  onPressed: _isBusy ? null : () => _pay(run),
                                  child: const Text('Payer'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
