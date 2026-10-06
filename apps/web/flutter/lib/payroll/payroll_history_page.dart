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

/// Historique des paies (demande utilisateur du 2026-10-05) : TOUTES les paies
/// (préparées, validées, payées, annulées), la plus récente d'abord, avec pour
/// chacune la ligne de chaque employé (nom, base, avance, ajustement, net).
/// Une paie non annulée peut être corrigée : période, avance/prime de chaque
/// employé — y compris après paiement (la dépense « Salaires » liée suit).
/// Filtrable sur une période choisie par l'utilisateur (paies dont la période
/// chevauche l'intervalle) ; le total des paies non annulées de la liste est
/// affiché en haut à droite.
class PayrollHistoryPage extends StatefulWidget {
  const PayrollHistoryPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<PayrollHistoryPage> createState() => _PayrollHistoryPageState();
}

class _PayrollHistoryPageState extends State<PayrollHistoryPage> {
  late final PayrollRepository _repository = PayrollRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final EmployeesRepository _employees = EmployeesRepository(
    ApiClient(),
    widget.establishmentId,
  );
  DateTimeRange? _period;
  late Future<List<PayrollRun>> _future = _fetch();
  bool _isBusy = false;

  Future<List<PayrollRun>> _fetch() =>
      _repository.listRuns(from: _period?.start, to: _period?.end);

  Future<void> _reload() async {
    final future = _fetch();
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _pickPeriod() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _period,
      helpText: 'Période des paies',
    );
    if (picked == null) return;
    _period = picked;
    await _reload();
  }

  Future<void> _clearPeriod() async {
    _period = null;
    await _reload();
  }

  /// Total des paies non annulées de la liste affichée.
  double _totalOf(List<PayrollRun> runs) => runs
      .where((r) => r.status != 'cancelled')
      .fold(0.0, (sum, r) => sum + r.total);

  Future<void> _addEmployee(PayrollRun run) async {
    if (_isBusy) return;
    List<Employee> employees;
    try {
      employees = await _employees.listEmployees();
    } catch (e) {
      _showError(e);
      return;
    }
    if (!mounted) return;
    final onRun = run.lines.map((l) => l.employeeId).toSet();
    final candidates = employees
        .where(
          (e) =>
              e.isActive &&
              e.salaryType == run.periodType &&
              !onRun.contains(e.id),
        )
        .toList();
    final employee = await showAddPayrollEmployeeDialog(
      context,
      candidates,
      paid: run.status == 'paid',
      monthly: run.isMonthly,
    );
    if (employee == null || _isBusy) return;
    setState(() => _isBusy = true);
    try {
      await _repository.addLine(run.id, employee.id);
      await _reload();
    } catch (e) {
      _showError(e);
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
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showError(Object e) {
    if (!mounted) return;
    final message = e is ApiException
        ? e.message
        : 'Opération impossible : connexion au serveur requise.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editLine(PayrollRun run, PayrollLine line) async {
    final values = await showPayrollLineDialog(
      context,
      line,
      paid: run.status == 'paid',
    );
    if (values == null || _isBusy) return;
    setState(() => _isBusy = true);
    try {
      await _repository.updateLine(
        run.id,
        line.id,
        advance: values.advance,
        adjustment: values.adjustment,
      );
      await _reload();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _editPeriod(PayrollRun run) async {
    final period = await showPayrollPeriodDialog(context, run);
    if (period == null || _isBusy) return;
    setState(() => _isBusy = true);
    try {
      await _repository.updateRun(
        run.id,
        periodStart: period.start,
        periodEnd: period.end,
      );
      await _reload();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final dateTimeFormat = DateFormat('dd/MM/yyyy à HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique des paies'),
        actions: [
          FutureBuilder<List<PayrollRun>>(
            future: _future,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Total des paies',
                      style: TextStyle(fontSize: 11),
                    ),
                    Text(
                      '${formatAmount(_totalOf(snapshot.data!))} FCFA',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildPeriodBar(dateFormat),
          Expanded(child: _buildList(dateFormat, dateTimeFormat)),
        ],
      ),
    );
  }

  Widget _buildPeriodBar(DateFormat dateFormat) {
    final period = _period;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickPeriod,
              icon: const Icon(Icons.date_range),
              label: Text(
                period == null
                    ? 'Toutes les périodes'
                    : 'Du ${dateFormat.format(period.start)} au ${dateFormat.format(period.end)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (period != null)
            IconButton(
              tooltip: 'Toutes les périodes',
              icon: const Icon(Icons.close),
              onPressed: _clearPeriod,
            ),
        ],
      ),
    );
  }

  /// Les paies (déjà triées de la plus récente à la plus ancienne) regroupées
  /// par mois de début de période, chaque groupe précédé d'un en-tête
  /// (« Octobre 2026 — 2 paies · 52 000 FCFA »).
  List<Widget> _buildItems(
    List<PayrollRun> runs,
    DateFormat dateFormat,
    DateFormat dateTimeFormat,
  ) {
    final items = <Widget>[];
    String? currentKey;
    for (final run in runs) {
      final key = '${run.periodStart.year}-${run.periodStart.month}';
      if (key != currentKey) {
        currentKey = key;
        final group = runs.where(
          (r) => '${r.periodStart.year}-${r.periodStart.month}' == key,
        );
        final active = group.where((r) => r.status != 'cancelled').toList();
        items.add(
          PayrollMonthHeader(
            month: run.periodStart,
            count: active.length,
            totalText:
                '${formatAmount(active.fold(0.0, (sum, r) => sum + r.total))} FCFA',
          ),
        );
      }
      items.add(_buildRunCard(run, dateFormat, dateTimeFormat));
    }
    return items;
  }

  Widget _buildRunCard(
    PayrollRun run,
    DateFormat dateFormat,
    DateFormat dateTimeFormat,
  ) {
    return PayrollRunCardFrame(
      run: run,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: PayrollRunTitle(run)),
              if (isPayrollRunEditable(run))
                IconButton(
                  tooltip: 'Modifier la période',
                  icon: const Icon(Icons.edit_calendar_outlined),
                  onPressed: _isBusy ? null : () => _editPeriod(run),
                ),
              PayrollStatusChip(run.status),
            ],
          ),
          const SizedBox(height: 6),
          if (run.createdAt != null)
            Text(
              'Préparée le ${dateTimeFormat.format(run.createdAt!.toLocal())}',
              style: const TextStyle(fontSize: 12),
            ),
          if (run.status == 'paid' && run.paidAt != null)
            Text(
              'Payée le ${dateTimeFormat.format(run.paidAt!.toLocal())}'
              ' — dépense « Salaires » du ${dateFormat.format(run.expenseDate ?? run.periodEnd)}',
              style: const TextStyle(fontSize: 12),
            ),
          const SizedBox(height: 4),
          if (run.lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Aucun employé sur cette paie.'),
            ),
          for (final line in run.lines)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(line.employeeName),
              subtitle: Text(
                'Base ${formatAmount(line.baseSalary)} — Avance ${formatAmount(line.advance)} — Ajust. ${formatAmount(line.adjustment)}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${formatAmount(line.netAmount)} F',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (isPayrollRunEditable(run)) ...[
                    IconButton(
                      tooltip: 'Modifier',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: _isBusy ? null : () => _editLine(run, line),
                    ),
                    IconButton(
                      tooltip: 'Retirer de la paie',
                      icon: const Icon(Icons.person_remove_outlined),
                      onPressed: _isBusy ? null : () => _removeLine(run, line),
                    ),
                  ],
                ],
              ),
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
            children: [
              if (run.lines.isNotEmpty)
                Text(
                  '${run.lines.length} employé${run.lines.length > 1 ? 's' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Total : ${formatAmount(run.total)} FCFA',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList(DateFormat dateFormat, DateFormat dateTimeFormat) {
    return FutureBuilder<List<PayrollRun>>(
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
          return Center(
            child: Text(
              _period == null
                  ? 'Aucune paie enregistrée.'
                  : 'Aucune paie sur cette période.',
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: _buildItems(runs, dateFormat, dateTimeFormat),
          ),
        );
      },
    );
  }
}
