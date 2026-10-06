import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/payroll/payroll_models.dart';
import 'package:chez_yasmine/payroll/payroll_run_widgets.dart';

PayrollRun run(String start, String end, {String type = 'weekly'}) =>
    PayrollRun(
      id: 'r',
      periodStart: DateTime.parse('${start}T00:00:00.000Z'),
      periodEnd: DateTime.parse('${end}T00:00:00.000Z'),
      status: 'prepared',
      lines: const [],
      periodType: type,
    );

/// Distinction nette des paies hebdomadaires et mensuelles (demande du
/// 2026-10-06) : titre lisible, type, repère relatif.
void main() {
  group('isoWeekNumber', () {
    test('semaines ISO 8601, y compris autour du changement d\'année', () {
      expect(isoWeekNumber(DateTime.utc(2026, 10, 5)), 41);
      expect(isoWeekNumber(DateTime.utc(2026, 9, 28)), 40);
      expect(
        isoWeekNumber(DateTime.utc(2025, 12, 29)),
        1,
        reason: 'le lundi 29/12/2025 ouvre la semaine 1 de 2026',
      );
      expect(isoWeekNumber(DateTime.utc(2026, 12, 28)), 53);
      expect(
        isoWeekNumber(DateTime.utc(2027, 1, 1)),
        53,
        reason: 'le vendredi 01/01/2027 est encore en semaine 53 de 2026',
      );
      expect(isoWeekNumber(DateTime.utc(2027, 1, 4)), 1);
    });
  });

  group('describePayrollRun', () {
    final now = DateTime(2026, 10, 7); // un mercredi, semaine 41

    test('paie hebdomadaire standard : « Semaine N » + repère relatif', () {
      final current = describePayrollRun(
        run('2026-10-05', '2026-10-11'),
        now: now,
      );
      expect(current.title, 'Semaine 41');
      expect(current.tag, 'Hebdo');
      expect(current.dates, '05/10/2026 → 11/10/2026');
      expect(current.relative, 'Semaine en cours');

      expect(
        describePayrollRun(run('2026-09-28', '2026-10-04'), now: now).relative,
        'Semaine dernière',
      );
      expect(
        describePayrollRun(run('2026-10-12', '2026-10-18'), now: now).relative,
        'Semaine prochaine',
      );
      expect(
        describePayrollRun(run('2026-09-14', '2026-09-20'), now: now).relative,
        isNull,
      );
    });

    test(
      'paie mensuelle sur un mois entier : « Mois Année » + repère relatif',
      () {
        final current = describePayrollRun(
          run('2026-10-01', '2026-10-31', type: 'monthly'),
          now: now,
        );
        expect(current.title, 'Octobre 2026');
        expect(current.tag, 'Mensuelle');
        expect(current.relative, 'Mois en cours');

        final last = describePayrollRun(
          run('2026-09-01', '2026-09-30', type: 'monthly'),
          now: now,
        );
        expect(last.title, 'Septembre 2026');
        expect(last.relative, 'Mois dernier');

        final february = describePayrollRun(
          run('2028-02-01', '2028-02-29', type: 'monthly'),
          now: now,
        );
        expect(
          february.title,
          'Février 2028',
          reason: 'année bissextile : fin de mois reconnue',
        );
      },
    );

    test('période modifiée à la main : « Période personnalisée » avec les dates exactes', () {
      final custom = describePayrollRun(
        run('2026-10-03', '2026-10-09'),
        now: now,
      );
      expect(custom.title, 'Période personnalisée');
      expect(custom.dates, '03/10/2026 → 09/10/2026');
      expect(custom.relative, 'En cours');

      final partialMonth = describePayrollRun(
        run('2026-09-01', '2026-09-15', type: 'monthly'),
        now: now,
      );
      expect(partialMonth.title, 'Période personnalisée');
      expect(partialMonth.tag, 'Mensuelle');
    });
  });
}
