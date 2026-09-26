import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _rangeDateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

/// Sélection d'un intervalle précis (date + heure + minute pour chaque
/// borne) — partagé entre l'Accueil (filtre Date) et Rapports > Boissons/
/// Plats vendus, pour filtrer exactement sur cet intervalle plutôt que sur
/// des jours calendaires entiers (décision utilisateur du 2026-09-26).
/// Retourne `null` si annulé.
Future<({DateTime from, DateTime to})?> pickDateTimeRange(
  BuildContext context, {
  required DateTime initialFrom,
  required DateTime initialTo,
}) {
  return showDialog<({DateTime from, DateTime to})>(
    context: context,
    builder: (dialogContext) {
      var from = initialFrom;
      var to = initialTo;
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> pickBound({required bool isFrom}) async {
            final current = isFrom ? from : to;
            final pickedDate = await showDatePicker(
              context: dialogContext,
              initialDate: current,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              helpText: isFrom ? 'Date de début' : 'Date de fin',
            );
            if (pickedDate == null) return;
            if (!dialogContext.mounted) return;
            final pickedTime = await showTimePicker(
              context: dialogContext,
              initialTime: TimeOfDay.fromDateTime(current),
              helpText: isFrom ? 'Heure de début' : 'Heure de fin',
            );
            if (pickedTime == null) return;
            final combined = DateTime(
              pickedDate.year,
              pickedDate.month,
              pickedDate.day,
              pickedTime.hour,
              pickedTime.minute,
            );
            setDialogState(() {
              if (isFrom) {
                from = combined;
              } else {
                to = combined;
              }
            });
          }

          final invalidRange = !to.isAfter(from);
          return AlertDialog(
            title: const Text('Choisir un intervalle'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Du'),
                  subtitle: Text(_rangeDateTimeFormat.format(from)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () => pickBound(isFrom: true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Au'),
                  subtitle: Text(_rangeDateTimeFormat.format(to)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () => pickBound(isFrom: false),
                ),
                if (invalidRange)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'La date de fin doit être après la date de début.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: invalidRange
                    ? null
                    : () => Navigator.of(dialogContext).pop((from: from, to: to)),
                child: const Text('Appliquer'),
              ),
            ],
          );
        },
      );
    },
  );
}
