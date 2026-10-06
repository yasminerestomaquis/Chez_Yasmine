import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import 'payroll_dialogs.dart';
import 'payroll_models.dart';

const _frenchMonths = [
  'Janvier',
  'Février',
  'Mars',
  'Avril',
  'Mai',
  'Juin',
  'Juillet',
  'Août',
  'Septembre',
  'Octobre',
  'Novembre',
  'Décembre',
];

/// « Octobre 2026 ».
String frenchMonthYear(DateTime date) =>
    '${_frenchMonths[date.month - 1]} ${date.year}';

/// Jour calendaire sans heure ni fuseau : les périodes de paie sont des dates
/// (`@db.Date`), reçues en UTC minuit — seuls année/mois/jour comptent.
DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Numéro de semaine ISO 8601 (la semaine 1 contient le premier jeudi).
int isoWeekNumber(DateTime date) {
  final day = _day(date);
  final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
  final firstDay = DateTime.utc(thursday.year, 1, 1);
  return thursday.difference(firstDay).inDays ~/ 7 + 1;
}

/// Identité visuelle d'une paie : un titre lisible (« Semaine 41 »,
/// « Septembre 2026 »), son type, les dates exactes et un repère relatif
/// (« Semaine en cours »…).
class PayrollRunLabel {
  const PayrollRunLabel({
    required this.title,
    required this.tag,
    required this.dates,
    this.relative,
  });

  final String title;

  /// « Hebdo » ou « Mensuelle ».
  final String tag;

  /// « 05/10/2026 → 11/10/2026 ».
  final String dates;
  final String? relative;
}

/// [now] injectable pour les tests.
PayrollRunLabel describePayrollRun(PayrollRun run, {DateTime? now}) {
  final fmt = DateFormat('dd/MM/yyyy');
  final start = _day(run.periodStart);
  final end = _day(run.periodEnd);
  final today = _day(now ?? DateTime.now());
  final dates = '${fmt.format(start)} → ${fmt.format(end)}';
  final tag = run.isMonthly ? 'Mensuelle' : 'Hebdo';

  if (run.isMonthly) {
    final lastDay = DateTime.utc(start.year, start.month + 1, 0);
    if (start.day == 1 && end == lastDay) {
      final monthsAgo =
          (today.year - start.year) * 12 + today.month - start.month;
      return PayrollRunLabel(
        title: frenchMonthYear(start),
        tag: tag,
        dates: dates,
        relative: switch (monthsAgo) {
          0 => 'Mois en cours',
          1 => 'Mois dernier',
          -1 => 'Mois prochain',
          _ => null,
        },
      );
    }
  } else if (start.weekday == DateTime.monday &&
      end == start.add(const Duration(days: 6))) {
    final currentMonday = today.subtract(Duration(days: today.weekday - 1));
    final weeksAgo = currentMonday.difference(start).inDays ~/ 7;
    return PayrollRunLabel(
      title: 'Semaine ${isoWeekNumber(start)}',
      tag: tag,
      dates: dates,
      relative: switch (weeksAgo) {
        0 => 'Semaine en cours',
        1 => 'Semaine dernière',
        -1 => 'Semaine prochaine',
        _ => null,
      },
    );
  }
  // Période modifiée à la main (ni semaine lundi→dimanche, ni mois entier).
  final containsToday = !today.isBefore(start) && !today.isAfter(end);
  return PayrollRunLabel(
    title: 'Période personnalisée',
    tag: tag,
    dates: dates,
    relative: containsToday ? 'En cours' : null,
  );
}

/// Couleur d'accent d'une paie : vert pour l'hebdomadaire, orange pour la
/// mensuelle — on distingue d'un coup d'œil les deux rythmes dans la liste.
Color payrollRunAccent(PayrollRun run) =>
    run.isMonthly ? AppColors.orange : AppColors.green;

({Color foreground, Color background}) payrollStatusColors(String status) =>
    switch (status) {
      'prepared' => (
        foreground: AppColors.orange,
        background: AppColors.orangeLight,
      ),
      'validated' => (
        foreground: const Color(0xFF1A56DB),
        background: const Color(0xFFE8F0FE),
      ),
      'paid' => (foreground: AppColors.green, background: AppColors.greenLight),
      'cancelled' => (
        foreground: AppColors.alert,
        background: AppColors.alertLight,
      ),
      _ => (
        foreground: AppColors.textSecondary,
        background: const Color(0xFFEFEAE6),
      ),
    };

class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.foreground, required this.background});

  final String text;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Pastille de statut colorée (Préparée / Validée / Payée / Annulée).
class PayrollStatusChip extends StatelessWidget {
  const PayrollStatusChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = payrollStatusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        payrollStatusLabel(status),
        style: TextStyle(
          color: colors.foreground,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Bloc titre d'une paie : « Semaine 41 » + pastilles (type, repère relatif)
/// + dates exactes.
class PayrollRunTitle extends StatelessWidget {
  const PayrollRunTitle(this.run, {super.key, this.now});

  final PayrollRun run;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final label = describePayrollRun(run, now: now);
    final accent = payrollRunAccent(run);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              label.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            _Pill(
              label.tag,
              foreground: accent,
              background: accent.withValues(alpha: 0.12),
            ),
            if (label.relative != null)
              _Pill(
                label.relative!,
                foreground: AppColors.textPrimary,
                background: const Color(0xFFEFEAE6),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label.dates,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Cadre d'une paie dans une liste : carte aérée, bandeau d'accent à gauche
/// (vert hebdomadaire / orange mensuel), atténuée si la paie est annulée.
class PayrollRunCardFrame extends StatelessWidget {
  const PayrollRunCardFrame({
    super.key,
    required this.run,
    required this.child,
  });

  final PayrollRun run;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: payrollRunAccent(run), width: 6),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: child,
      ),
    );
    return run.status == 'cancelled'
        ? Opacity(opacity: 0.65, child: card)
        : card;
  }
}

/// En-tête de groupe mensuel de l'historique : « Octobre 2026 — 2 paies · 52 000 FCFA ».
class PayrollMonthHeader extends StatelessWidget {
  const PayrollMonthHeader({
    super.key,
    required this.month,
    required this.count,
    required this.totalText,
  });

  final DateTime month;
  final int count;
  final String totalText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              frenchMonthYear(month),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            '$count paie${count > 1 ? 's' : ''} · $totalText',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
