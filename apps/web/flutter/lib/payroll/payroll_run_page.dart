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

  Future<void> _reload() async {
    final future = _repository.listRuns();
    setState(() => _future = future);
    await future;
  }

  Future<void> _prepare() async {
    if (_isBusy) return;
    final monday = _mondayOf(DateTime.now());
    final sunday = monday.add(const Duration(days: 6));
    setState(() => _isBusy = true);
    try {
      await _repository.prepare(periodStart: monday, periodEnd: sunday);
      // Attendu explicitement : le backend n'a aucune contrainte d'unicité
      // de période (voir Task 4), donc `_isBusy` seul ne protège que la
      // fenêtre de l'appel réseau — `await` ici (pas de fire-and-forget)
      // garantit que la liste rechargée est affichée AVANT de réactiver le
      // FAB, fermant la fenêtre où un second appui créerait un doublon.
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
    final advanceController = TextEditingController(
      text: line.advance.toStringAsFixed(0),
    );
    final adjustmentController = TextEditingController(
      text: line.adjustment.toStringAsFixed(0),
    );
    final formKey = GlobalKey<FormState>();
    // Une saisie non numérique doit bloquer l'enregistrement plutôt que de
    // silencieusement écraser l'avance/l'ajustement existant par 0 — même
    // niveau de rigueur que employee_form_dialog.dart.
    String? validateAmount(String? v) {
      final value = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
      return value == null ? 'Montant invalide' : null;
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(line.employeeName),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: advanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Avance'),
                validator: validateAmount,
              ),
              TextFormField(
                controller: adjustmentController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Prime (+) / Retenue (-)',
                ),
                validator: validateAmount,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(context).pop(true);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await _repository.updateLine(
        run.id,
        line.id,
        advance: double.parse(
          advanceController.text.trim().replaceAll(',', '.'),
        ),
        adjustment: double.parse(
          adjustmentController.text.trim().replaceAll(',', '.'),
        ),
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

  String _statusLabel(String status) => switch (status) {
    'prepared' => 'Préparée',
    'validated' => 'Validée',
    'paid' => 'Payée',
    'cancelled' => 'Annulée',
    _ => status,
  };

  /// Vrai si une paie non annulée de la semaine en cours existe déjà — le
  /// backend n'a aucune contrainte d'unicité de période (voir
  /// PayrollService.prepare), donc c'est la seule protection contre un
  /// doublon si l'utilisateur ré-appuie sur "Préparer" alors qu'une paie de
  /// cette semaine est déjà `prepared`/`validated`/`paid`.
  bool _alreadyPreparedThisWeek(List<PayrollRun> runs) {
    final monday = _mondayOf(DateTime.now());
    return runs.any(
      (r) => r.status != 'cancelled' && r.periodStart.isAtSameMomentAs(monday),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy');
    return Scaffold(
      appBar: AppBar(title: const Text('Préparer la paie')),
      floatingActionButton: FutureBuilder<List<PayrollRun>>(
        future: _future,
        builder: (context, snapshot) {
          final alreadyPrepared =
              snapshot.data != null && _alreadyPreparedThisWeek(snapshot.data!);
          return FloatingActionButton.extended(
            onPressed: (_isBusy || alreadyPrepared) ? null : _prepare,
            icon: const Icon(Icons.add),
            label: Text(
              alreadyPrepared
                  ? 'Paie de la semaine déjà préparée'
                  : 'Préparer la semaine en cours',
            ),
          );
        },
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
                            onTap: (run.status == 'prepared' && !_isBusy)
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
                ),
            ],
          );
        },
      ),
    );
  }
}
