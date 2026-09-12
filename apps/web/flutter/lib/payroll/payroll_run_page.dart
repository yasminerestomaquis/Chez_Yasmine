import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../common/formatting.dart';
import 'payroll_models.dart';
import 'payroll_repository.dart';

DateTime _mondayOf(DateTime date) {
  final weekdayIndex = (date.weekday - 1) % 7;
  return DateTime(
    date.year,
    date.month,
    date.day,
  ).subtract(Duration(days: weekdayIndex));
}

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
  late Future<List<PayrollRun>> _future = _repository.listRuns();
  bool _isBusy = false;

  void _reload() => setState(() => _future = _repository.listRuns());

  Future<void> _prepare() async {
    final monday = _mondayOf(DateTime.now());
    final sunday = monday.add(const Duration(days: 6));
    setState(() => _isBusy = true);
    try {
      await _repository.prepare(periodStart: monday, periodEnd: sunday);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _editLine(PayrollRun run, PayrollLine line) async {
    final advanceController = TextEditingController(
      text: line.advance.toStringAsFixed(0),
    );
    final adjustmentController = TextEditingController(
      text: line.adjustment.toStringAsFixed(0),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(line.employeeName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: advanceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Avance'),
            ),
            TextField(
              controller: adjustmentController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Prime (+) / Retenue (-)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await _repository.updateLine(
        run.id,
        line.id,
        advance:
            double.tryParse(advanceController.text.replaceAll(',', '.')) ?? 0,
        adjustment:
            double.tryParse(adjustmentController.text.replaceAll(',', '.')) ??
            0,
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _validate(PayrollRun run) async {
    try {
      await _repository.validate(run.id);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
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
    try {
      await _repository.pay(run.id);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _cancel(PayrollRun run) async {
    try {
      await _repository.cancel(run.id);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _statusLabel(String status) => switch (status) {
    'prepared' => 'Préparée',
    'validated' => 'Validée',
    'paid' => 'Payée',
    'cancelled' => 'Annulée',
    _ => status,
  };

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy');
    return Scaffold(
      appBar: AppBar(title: const Text('Préparer la paie')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBusy ? null : _prepare,
        icon: const Icon(Icons.add),
        label: const Text('Préparer la semaine en cours'),
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
                                'Du ${fmt.format(run.periodStart)} au ${fmt.format(run.periodEnd)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Chip(label: Text(_statusLabel(run.status))),
                          ],
                        ),
                        for (final line in run.lines)
                          ListTile(
                            dense: true,
                            title: Text(line.employeeName),
                            subtitle: Text(
                              'Base ${formatAmount(line.baseSalary)} — Avance ${formatAmount(line.advance)} — Ajust. ${formatAmount(line.adjustment)}',
                            ),
                            trailing: Text(
                              '${formatAmount(line.netAmount)} F',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: run.status == 'prepared'
                                ? () => _editLine(run, line)
                                : null,
                          ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total : ${formatAmount(run.total)} FCFA',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                if (run.status == 'prepared') ...[
                                  TextButton(
                                    onPressed: () => _cancel(run),
                                    child: const Text('Annuler'),
                                  ),
                                  FilledButton(
                                    onPressed: () => _validate(run),
                                    child: const Text('Valider'),
                                  ),
                                ],
                                if (run.status == 'validated') ...[
                                  TextButton(
                                    onPressed: () => _cancel(run),
                                    child: const Text('Annuler'),
                                  ),
                                  FilledButton(
                                    onPressed: () => _pay(run),
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
                ),
            ],
          );
        },
      ),
    );
  }
}
