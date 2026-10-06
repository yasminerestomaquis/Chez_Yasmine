import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../common/formatting.dart';
import 'employee_models.dart';
import 'payroll_models.dart';

/// Libellé français du statut d'une paie.
String payrollStatusLabel(String status) => switch (status) {
  'prepared' => 'Préparée',
  'validated' => 'Validée',
  'paid' => 'Payée',
  'cancelled' => 'Annulée',
  _ => status,
};

/// Une paie annulée est figée ; préparée, validée ou payée, elle reste
/// corrigeable (historique des paies, demande du 2026-10-05).
bool isPayrollRunEditable(PayrollRun run) => run.status != 'cancelled';

/// Avance et prime/retenue d'un employé pour une paie. Renvoie `null` si
/// l'utilisateur annule. [paid] : la paie est déjà payée — un avertissement
/// précise alors que la dépense « Salaires » liée sera ajustée.
Future<({double advance, double adjustment})?> showPayrollLineDialog(
  BuildContext context,
  PayrollLine line, {
  bool paid = false,
}) async {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (paid)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Cette paie est déjà payée : la dépense « Salaires » '
                  'correspondante sera ajustée au nouveau total.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
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
  if (saved != true) return null;
  return (
    advance: double.parse(advanceController.text.trim().replaceAll(',', '.')),
    adjustment: double.parse(
      adjustmentController.text.trim().replaceAll(',', '.'),
    ),
  );
}

/// Choix de l'employé à ajouter à une paie parmi [candidates] (employés actifs
/// absents de la paie). Renvoie `null` si l'utilisateur annule ou s'il n'y a
/// personne à ajouter.
Future<Employee?> showAddPayrollEmployeeDialog(
  BuildContext context,
  List<Employee> candidates, {
  bool paid = false,
}) {
  if (candidates.isEmpty) {
    return showDialog<Employee>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajouter un employé'),
        content: const Text(
          'Tous les employés actifs figurent déjà sur cette paie.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
  return showDialog<Employee>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Ajouter un employé'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (paid)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Cette paie est déjà payée : la dépense « Salaires » '
                  'correspondante sera ajustée au nouveau total.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            for (final employee in candidates)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(employee.fullName),
                subtitle: Text(
                  '${employee.position} — ${formatAmount(employee.weeklySalary)} F / semaine',
                ),
                onTap: () => Navigator.of(context).pop(employee),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
      ],
    ),
  );
}

/// Confirmation du retrait d'un employé d'une paie.
Future<bool> confirmRemovePayrollLine(
  BuildContext context,
  PayrollLine line, {
  bool paid = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Retirer cet employé ?'),
      content: Text(
        '${line.employeeName} ne figurera plus sur cette paie'
        '${paid ? ' et la dépense « Salaires » correspondante sera ajustée au nouveau total' : ''}.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Retirer'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Période (« Du … au … ») d'une paie. Renvoie `null` si l'utilisateur annule.
Future<({DateTime start, DateTime end})?> showPayrollPeriodDialog(
  BuildContext context,
  PayrollRun run,
) {
  var start = DateTime(
    run.periodStart.year,
    run.periodStart.month,
    run.periodStart.day,
  );
  var end = DateTime(
    run.periodEnd.year,
    run.periodEnd.month,
    run.periodEnd.day,
  );
  final format = DateFormat('dd/MM/yyyy');

  Future<DateTime?> pick(BuildContext context, DateTime initial, String help) {
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: help,
    );
  }

  return showDialog<({DateTime start, DateTime end})>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final invalid = end.isBefore(start);
        return AlertDialog(
          title: const Text('Période de la paie'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (run.status == 'paid')
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Cette paie est déjà payée : la date de la dépense '
                    '« Salaires » suivra la fin de période.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await pick(context, start, 'Début de période');
                  if (picked != null) setDialogState(() => start = picked);
                },
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text('Du ${format.format(start)}'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await pick(context, end, 'Fin de période');
                  if (picked != null) setDialogState(() => end = picked);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text('Au ${format.format(end)}'),
              ),
              if (invalid)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'La fin de période ne peut pas précéder le début.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: invalid
                  ? null
                  : () => Navigator.of(context).pop((start: start, end: end)),
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    ),
  );
}
