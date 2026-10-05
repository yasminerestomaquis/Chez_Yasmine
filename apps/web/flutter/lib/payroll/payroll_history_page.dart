import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../common/formatting.dart';
import 'payroll_dialogs.dart';
import 'payroll_models.dart';
import 'payroll_repository.dart';

/// Historique des paies (demande utilisateur du 2026-10-05) : TOUTES les paies
/// (préparées, validées, payées, annulées), la plus récente d'abord, avec pour
/// chacune la ligne de chaque employé (nom, base, avance, ajustement, net).
/// Une paie non annulée peut être corrigée : période, avance/prime de chaque
/// employé — y compris après paiement (la dépense « Salaires » liée suit).
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
  late Future<List<PayrollRun>> _future = _repository.listRuns();
  bool _isBusy = false;

  Future<void> _reload() async {
    final future = _repository.listRuns();
    setState(() => _future = future);
    await future;
  }

  void _showError(Object e) {
    if (!mounted) return;
    final message = e is ApiException
        ? e.message
        : 'Opération impossible : connexion au serveur requise.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      appBar: AppBar(title: const Text('Historique des paies')),
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
            return const Center(child: Text('Aucune paie enregistrée.'));
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final run in runs)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Du ${dateFormat.format(run.periodStart)} au ${dateFormat.format(run.periodEnd)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (isPayrollRunEditable(run))
                                IconButton(
                                  tooltip: 'Modifier la période',
                                  icon: const Icon(Icons.edit_calendar_outlined),
                                  onPressed: _isBusy
                                      ? null
                                      : () => _editPeriod(run),
                                ),
                              Chip(label: Text(payrollStatusLabel(run.status))),
                            ],
                          ),
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
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (isPayrollRunEditable(run))
                                    IconButton(
                                      tooltip: 'Modifier',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: _isBusy
                                          ? null
                                          : () => _editLine(run, line),
                                    ),
                                ],
                              ),
                            ),
                          const Divider(),
                          Text(
                            'Total : ${formatAmount(run.total)} FCFA',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
