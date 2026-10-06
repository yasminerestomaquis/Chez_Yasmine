import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/expenses/expenses_form_tab.dart';
import 'package:chez_yasmine/expenses/expenses_page.dart';
import 'package:chez_yasmine/payroll/payroll_history_page.dart';
import 'package:chez_yasmine/payroll/payroll_run_page.dart';

/// Demande du 2026-10-05 : date de saisie + modification des dépenses ;
/// historique des paies (employés nommés) avec modification de la période et
/// des lignes.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  final sent = <http.Request>[];

  http.Response json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  setUp(sent.clear);

  Map<String, dynamic> expense(
    String id, {
    String? payrollRunId,
    String category = 'Bouteilles de gaz',
  }) => {
    'id': id,
    'label': payrollRunId == null ? 'Gaz' : 'Paiement des salaires',
    'category': category,
    'amount': 12500,
    'expenseDate': '2026-10-02T00:00:00.000Z',
    'periodicity': 'one_off',
    'note': null,
    'marketNumber': null,
    'paymentMethod': 'cash',
    'status': 'paid',
    'payrollRunId': payrollRunId,
    'createdAt': '2026-10-03T14:30:00.000Z',
  };

  group('Dépenses : date de saisie et modification', () {
    MockClient expensesServer() => MockClient((request) async {
      sent.add(request);
      if (request.method == 'GET') {
        return json([
          expense('e1'),
          expense('e2', payrollRunId: 'run-1', category: 'Salaires'),
        ]);
      }
      return json(expense('e1'));
    });

    testWidgets(
      'chaque dépense affiche sa date de saisie ; seule la dépense manuelle est modifiable',
      (tester) async {
        await http.runWithClient(() async {
          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(body: ExpensesFormTab(establishmentId: 'est-1')),
            ),
          );
          await tester.pumpAndSettle();

          final expected = DateFormat('dd/MM/yyyy à HH:mm')
              .format(DateTime.parse('2026-10-03T14:30:00.000Z').toLocal());
          expect(find.text('Gaz'), findsOneWidget);
          expect(find.textContaining('Saisie le $expected'), findsNWidgets(2));
          expect(
            find.byTooltip('Modifier'),
            findsOneWidget,
            reason: 'la dépense de paie n\'est pas modifiable ici',
          );
        }, expensesServer);
      },
    );

    testWidgets(
      'Modifier : formulaire pré-rempli, enregistrement par PATCH avec les nouvelles valeurs',
      (tester) async {
        await http.runWithClient(() async {
          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(body: ExpensesFormTab(establishmentId: 'est-1')),
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.byTooltip('Modifier'));
          await tester.pumpAndSettle();

          expect(find.text('Modifier la dépense'), findsOneWidget);
          expect(
            tester
                .widget<TextFormField>(
                  find.widgetWithText(TextFormField, 'Libellé *'),
                )
                .controller!
                .text,
            'Gaz',
          );
          expect(
            tester
                .widget<TextFormField>(
                  find.widgetWithText(TextFormField, 'Montant *'),
                )
                .controller!
                .text,
            '12500',
          );
          expect(find.text('Date : 02/10/2026'), findsOneWidget);

          await tester.enterText(
            find.widgetWithText(TextFormField, 'Libellé *'),
            'Gaz 12 kg',
          );
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Montant *'),
            '13000',
          );
          await tester.tap(find.text('Enregistrer'));
          await tester.pumpAndSettle();

          final patch = sent.singleWhere((r) => r.method == 'PATCH');
          expect(patch.url.path, endsWith('/expenses/e1'));
          final body = jsonDecode(patch.body) as Map<String, dynamic>;
          expect(body['label'], 'Gaz 12 kg');
          expect(body['amount'], 13000);
          expect(body['expenseDate'], '2026-10-02');
          expect(body['category'], 'Bouteilles de gaz');
          expect(body['paymentMethod'], 'cash');
          expect(body['status'], 'paid');
        }, expensesServer);
      },
    );

    testWidgets('Modifier puis Annuler : aucune requête de modification', (
      tester,
    ) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: ExpensesFormTab(establishmentId: 'est-1')),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Modifier'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Annuler').last);
        await tester.pumpAndSettle();

        expect(sent.where((r) => r.method == 'PATCH'), isEmpty);
      }, expensesServer);
    });
  });

  group('Historique des paies', () {
    Map<String, dynamic> line(
      String id,
      String last,
      String first,
      int base, {
      int advance = 0,
    }) => {
      'id': id,
      'employeeId': 'emp-$id',
      'baseSalary': base,
      'advance': advance,
      'adjustment': 0,
      'netAmount': base - advance,
      'employee': {'id': 'emp-$id', 'lastName': last, 'firstName': first},
    };

    final runs = [
      {
        'id': 'run-a',
        'periodStart': '2026-09-28T00:00:00.000Z',
        'periodEnd': '2026-10-04T00:00:00.000Z',
        'status': 'paid',
        'createdAt': '2026-10-01T09:00:00.000Z',
        'paidAt': '2026-10-04T18:00:00.000Z',
        'expense': {
          'id': 'e9',
          'amount': 55000,
          'expenseDate': '2026-10-04T00:00:00.000Z',
        },
        'lines': [
          line('l1', 'Koffi', 'Awa', 30000),
          line('l2', 'Traoré', 'Moussa', 25000),
        ],
      },
      {
        'id': 'run-b',
        'periodStart': '2026-09-21T00:00:00.000Z',
        'periodEnd': '2026-09-27T00:00:00.000Z',
        'status': 'cancelled',
        'createdAt': '2026-09-22T09:00:00.000Z',
        'paidAt': null,
        'expense': null,
        'lines': [line('l3', 'Yao', 'Jean', 20000)],
      },
    ];

    MockClient payrollServer() => MockClient((request) async {
      sent.add(request);
      return request.method == 'GET' ? json(runs) : json({});
    });

    Future<void> openHistory(WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PayrollHistoryPage(establishmentId: 'est-1')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'liste toutes les paies, avec le nom de chaque employé ; une paie annulée n\'est pas modifiable',
      (tester) async {
        await http.runWithClient(() async {
          await openHistory(tester);

          expect(find.text('Koffi Awa'), findsOneWidget);
          expect(find.text('Traoré Moussa'), findsOneWidget);
          expect(
            find.text('Yao Jean'),
            findsOneWidget,
            reason: 'les paies annulées restent dans l\'historique',
          );
          expect(find.text('Payée'), findsOneWidget);
          expect(find.text('Annulée'), findsOneWidget);
          expect(find.textContaining('Total : 55 000'), findsOneWidget);
          // Paie payée : période + 2 lignes modifiables ; paie annulée : rien.
          expect(find.byTooltip('Modifier la période'), findsOneWidget);
          expect(find.byTooltip('Modifier'), findsNWidgets(2));
        }, payrollServer);
      },
    );

    testWidgets(
      'modifier la ligne d\'un employé (paie déjà payée) : avertissement puis PATCH',
      (tester) async {
        await http.runWithClient(() async {
          await openHistory(tester);

          await tester.tap(find.byTooltip('Modifier').first);
          await tester.pumpAndSettle();
          expect(find.textContaining('déjà payée'), findsOneWidget);

          await tester.enterText(
            find.widgetWithText(TextFormField, 'Avance'),
            '2000',
          );
          await tester.tap(find.text('Enregistrer'));
          await tester.pumpAndSettle();

          final patch = sent.singleWhere((r) => r.method == 'PATCH');
          expect(patch.url.path, endsWith('/payroll/runs/run-a/lines/l1'));
          final body = jsonDecode(patch.body) as Map<String, dynamic>;
          expect(body['advance'], 2000);
          expect(body['adjustment'], 0);
        }, payrollServer);
      },
    );

    testWidgets('modifier la période : PATCH avec les deux dates', (
      tester,
    ) async {
      await http.runWithClient(() async {
        await openHistory(tester);

        await tester.tap(find.byTooltip('Modifier la période'));
        await tester.pumpAndSettle();
        expect(find.text('Période de la paie'), findsOneWidget);
        expect(find.text('Du 28/09/2026'), findsOneWidget);
        expect(find.text('Au 04/10/2026'), findsOneWidget);

        await tester.tap(find.text('Enregistrer'));
        await tester.pumpAndSettle();

        final patch = sent.singleWhere((r) => r.method == 'PATCH');
        expect(patch.url.path, endsWith('/payroll/runs/run-a'));
        final body = jsonDecode(patch.body) as Map<String, dynamic>;
        expect(body['periodStart'], '2026-09-28');
        expect(body['periodEnd'], '2026-10-04');
      }, payrollServer);
    });

    Map<String, dynamic> employeeJson(
      String id,
      String last,
      String first, {
      String status = 'active',
    }) => {
      'id': id,
      'lastName': last,
      'firstName': first,
      'phone': '0700000000',
      'position': 'Serveur',
      'hireDate': '2026-01-01T00:00:00.000Z',
      'weeklySalary': 20000,
      'status': status,
    };

    MockClient fullServer() => MockClient((request) async {
      sent.add(request);
      if (request.method == 'GET' && request.url.path.endsWith('/employees')) {
        return json([
          employeeJson(
            'emp-l1',
            'Koffi',
            'Awa',
          ), // déjà sur la paie run-a (ligne l1)
          employeeJson('emp-new', 'Diallo', 'Fanta'),
          employeeJson('emp-off', 'Sorti', 'Paul', status: 'inactive'),
        ]);
      }
      return request.method == 'GET' ? json(runs) : json({});
    });

    testWidgets(
      'le total des paies (hors annulées) s\'affiche en haut à droite',
      (tester) async {
        await http.runWithClient(() async {
          await openHistory(tester);

          final appBar = find.byType(AppBar);
          expect(
            find.descendant(of: appBar, matching: find.text('Total des paies')),
            findsOneWidget,
          );
          // 55 000 (payée) — la paie annulée de 20 000 n'est pas comptée.
          expect(
            find.descendant(of: appBar, matching: find.text('55 000 FCFA')),
            findsOneWidget,
          );
        }, payrollServer);
      },
    );

    testWidgets('filtrer sur une période : la requête porte from/to', (
      tester,
    ) async {
      await http.runWithClient(() async {
        await openHistory(tester);
        expect(find.text('Toutes les périodes'), findsOneWidget);
        expect(
          sent.where((r) => r.method == 'GET').single.url.queryParameters,
          isEmpty,
        );

        await tester.tap(find.text('Toutes les périodes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('10').first);
        await tester.pump();
        await tester.tap(find.text('20').first);
        await tester.pump();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        final now = DateTime.now();
        String two(int n) => n.toString().padLeft(2, '0');
        final month = '${now.year}-${two(now.month)}';
        final last = sent.where((r) => r.method == 'GET').last;
        expect(last.url.queryParameters, {
          'from': '$month-10',
          'to': '$month-20',
        });
        expect(
          find.text(
            'Du 10/${two(now.month)}/${now.year} au 20/${two(now.month)}/${now.year}',
          ),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('Toutes les périodes'));
        await tester.pumpAndSettle();
        expect(
          sent.where((r) => r.method == 'GET').last.url.queryParameters,
          isEmpty,
        );
      }, payrollServer);
    });

    testWidgets(
      'ajouter un employé : seuls les employés actifs absents de la paie sont proposés, puis POST',
      (tester) async {
        await http.runWithClient(() async {
          await openHistory(tester);

          await tester.tap(find.text('Ajouter un employé').first);
          await tester.pumpAndSettle();
          expect(find.text('Diallo Fanta'), findsOneWidget);
          expect(
            find.text('Sorti Paul'),
            findsNothing,
            reason: 'employé inactif',
          );
          // Koffi Awa est déjà sur la paie : il n'est pas proposé dans la boîte de dialogue.
          expect(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Koffi Awa'),
            ),
            findsNothing,
          );
          expect(find.textContaining('déjà payée'), findsOneWidget);

          await tester.tap(find.text('Diallo Fanta'));
          await tester.pumpAndSettle();

          final post = sent.singleWhere((r) => r.method == 'POST');
          expect(post.url.path, endsWith('/payroll/runs/run-a/lines'));
          expect(jsonDecode(post.body), {'employeeId': 'emp-new'});
        }, fullServer);
      },
    );

    testWidgets('retirer un employé : confirmation puis DELETE de sa ligne', (
      tester,
    ) async {
      await http.runWithClient(() async {
        await openHistory(tester);

        await tester.tap(find.byTooltip('Retirer de la paie').first);
        await tester.pumpAndSettle();
        expect(find.text('Retirer cet employé ?'), findsOneWidget);
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        expect(sent.where((r) => r.method == 'DELETE'), isEmpty);

        await tester.tap(find.byTooltip('Retirer de la paie').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Retirer'));
        await tester.pumpAndSettle();

        final delete = sent.singleWhere((r) => r.method == 'DELETE');
        expect(delete.url.path, endsWith('/payroll/runs/run-a/lines/l1'));
      }, payrollServer);
    });

    testWidgets('une paie annulée n\'a ni bouton Ajouter ni bouton Retirer', (
      tester,
    ) async {
      await http.runWithClient(() async {
        await openHistory(tester);
        // run-a (payée) : 2 lignes + 1 bouton d'ajout ; run-b (annulée) : rien.
        expect(find.byTooltip('Retirer de la paie'), findsNWidgets(2));
        expect(find.text('Ajouter un employé'), findsOneWidget);
      }, payrollServer);
    });
  });

  group('Module Dépenses : accès à l\'historique des paies', () {
    testWidgets(
      'le bouton de l\'en-tête ouvre l\'historique de toutes les paies',
      (tester) async {
        final server = MockClient((request) async {
          sent.add(request);
          if (request.url.path.endsWith('/payroll/runs')) {
            return json([
              {
                'id': 'run-a',
                'periodStart': '2026-09-28T00:00:00.000Z',
                'periodEnd': '2026-10-04T00:00:00.000Z',
                'status': 'prepared',
                'lines': <Object>[],
              },
            ]);
          }
          return json(<Object>[]);
        });
        await http.runWithClient(() async {
          await tester.pumpWidget(
            const MaterialApp(home: ExpensesPage(establishmentId: 'est-1')),
          );
          await tester.pump(const Duration(milliseconds: 500));

          await tester.tap(find.byTooltip('Historique des paies'));
          await tester.pumpAndSettle();

          expect(find.text('Historique des paies'), findsWidgets);
          expect(find.text('Toutes les périodes'), findsOneWidget);
          expect(sent.any((r) => r.url.path.endsWith('/payroll/runs')), isTrue);
        }, () => server);
      },
    );
  });

  group('Préparer la paie : employés de la paie', () {
    final preparedRun = {
      'id': 'run-p',
      'periodStart': '2026-10-05T00:00:00.000Z',
      'periodEnd': '2026-10-11T00:00:00.000Z',
      'status': 'prepared',
      'createdAt': '2026-10-05T20:55:00.000Z',
      'paidAt': null,
      'expense': null,
      'lines': [
        {
          'id': 'lp1',
          'employeeId': 'emp-a',
          'baseSalary': 15000,
          'advance': 0,
          'adjustment': 0,
          'netAmount': 15000,
          'employee': {
            'id': 'emp-a',
            'lastName': 'Sapero',
            'firstName': 'Manadja',
          },
        },
      ],
    };

    MockClient server() => MockClient((request) async {
      sent.add(request);
      if (request.method == 'GET' && request.url.path.endsWith('/employees')) {
        return json([
          {
            'id': 'emp-a',
            'lastName': 'Sapero',
            'firstName': 'Manadja',
            'phone': '0700000000',
            'position': 'Serveuse',
            'hireDate': '2026-01-01T00:00:00.000Z',
            'weeklySalary': 15000,
            'status': 'active',
          },
          {
            'id': 'emp-b',
            'lastName': 'Diallo',
            'firstName': 'Fanta',
            'phone': '0700000001',
            'position': 'Cuisinière',
            'hireDate': '2026-01-01T00:00:00.000Z',
            'weeklySalary': 20000,
            'status': 'active',
          },
        ]);
      }
      return request.method == 'GET' ? json([preparedRun]) : json({});
    });

    testWidgets('ajouter puis retirer un employé sur la paie préparée', (
      tester,
    ) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(
          const MaterialApp(home: PayrollRunPage(establishmentId: 'est-1')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Ajouter un employé'));
        await tester.pumpAndSettle();
        expect(find.text('Diallo Fanta'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Sapero Manadja'),
          ),
          findsNothing,
        );
        await tester.tap(find.text('Diallo Fanta'));
        await tester.pumpAndSettle();
        final post = sent.singleWhere((r) => r.method == 'POST');
        expect(post.url.path, endsWith('/payroll/runs/run-p/lines'));
        expect(jsonDecode(post.body), {'employeeId': 'emp-b'});

        await tester.tap(find.byTooltip('Retirer de la paie'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Retirer'));
        await tester.pumpAndSettle();
        expect(
          sent.singleWhere((r) => r.method == 'DELETE').url.path,
          endsWith('/payroll/runs/run-p/lines/lp1'),
        );
      }, server);
    });
  });

  group('Préparer la paie : semaine omise et paie mensuelle', () {
    List<Map<String, dynamic>> existing = [];

    MockClient server() => MockClient((request) async {
      sent.add(request);
      if (request.method == 'GET') return json(existing);
      return json({
        'id': 'run-new',
        'periodStart': '2026-01-01T00:00:00.000Z',
        'periodEnd': '2026-01-07T00:00:00.000Z',
        'status': 'prepared',
        'lines': <Object>[],
      });
    });

    String two(int n) => n.toString().padLeft(2, '0');
    String iso(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

    Future<void> pickDay10AndConfirm(WidgetTester tester) async {
      await tester.tap(find.text('10').first);
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    }

    setUp(() => existing = []);

    testWidgets('une semaine omise se prépare en choisissant un de ses jours', (
      tester,
    ) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(
          const MaterialApp(home: PayrollRunPage(establishmentId: 'est-1')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Préparer une paie'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Une autre semaine (semaine omise)'));
        await tester.pumpAndSettle();
        await pickDay10AndConfirm(tester);
        expect(find.text('Préparer cette paie ?'), findsOneWidget);
        await tester.tap(find.text('Préparer'));
        await tester.pumpAndSettle();

        final now = DateTime.now();
        final day = DateTime(now.year, now.month, 10);
        final monday = day.subtract(Duration(days: day.weekday - 1));
        final post = sent.singleWhere((r) => r.method == 'POST');
        expect(post.url.path, endsWith('/payroll/runs'));
        expect(jsonDecode(post.body), {
          'periodStart': iso(monday),
          'periodEnd': iso(monday.add(const Duration(days: 6))),
          'periodType': 'weekly',
        });
      }, server);
    });

    testWidgets('la paie mensuelle couvre le mois du jour choisi', (
      tester,
    ) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(
          const MaterialApp(home: PayrollRunPage(establishmentId: 'est-1')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Préparer une paie'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paie mensuelle'));
        await tester.pumpAndSettle();
        await pickDay10AndConfirm(tester);
        await tester.tap(find.text('Préparer'));
        await tester.pumpAndSettle();

        final now = DateTime.now();
        final post = sent.singleWhere((r) => r.method == 'POST');
        expect(jsonDecode(post.body), {
          'periodStart': iso(DateTime(now.year, now.month, 1)),
          'periodEnd': iso(DateTime(now.year, now.month + 1, 0)),
          'periodType': 'monthly',
        });
      }, server);
    });

    testWidgets('une période déjà préparée n\'est pas préparée deux fois', (
      tester,
    ) async {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, 10);
      final monday = day.subtract(Duration(days: day.weekday - 1));
      existing = [
        {
          'id': 'run-x',
          'periodStart': '${iso(monday)}T00:00:00.000Z',
          'periodEnd':
              '${iso(monday.add(const Duration(days: 6)))}T00:00:00.000Z',
          'status': 'prepared',
          'periodType': 'weekly',
          'lines': <Object>[],
        },
      ];
      await http.runWithClient(() async {
        await tester.pumpWidget(
          const MaterialApp(home: PayrollRunPage(establishmentId: 'est-1')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Préparer une paie'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Une autre semaine (semaine omise)'));
        await tester.pumpAndSettle();
        await pickDay10AndConfirm(tester);
        await tester.tap(find.text('Préparer'));
        await tester.pumpAndSettle();

        expect(
          find.text('Une paie existe déjà pour cette période.'),
          findsOneWidget,
        );
        expect(sent.where((r) => r.method == 'POST'), isEmpty);
      }, server);
    });

    testWidgets(
      'une paie mensuelle est signalée et n\'accepte que les employés payés au mois',
      (tester) async {
        existing = [
          {
            'id': 'run-m',
            'periodStart': '2026-09-01T00:00:00.000Z',
            'periodEnd': '2026-09-30T00:00:00.000Z',
            'status': 'prepared',
            'periodType': 'monthly',
            'lines': <Object>[],
          },
        ];
        final srv = MockClient((request) async {
          sent.add(request);
          if (request.method == 'GET' &&
              request.url.path.endsWith('/employees')) {
            Map<String, dynamic> e(String id, String last, String type) => {
              'id': id,
              'lastName': last,
              'firstName': 'X',
              'phone': '0700000000',
              'position': 'Serveur',
              'hireDate': '2026-01-01T00:00:00.000Z',
              'weeklySalary': 100000,
              'salaryType': type,
              'status': 'active',
            };
            return json([
              e('e1', 'Mensuel', 'monthly'),
              e('e2', 'Hebdo', 'weekly'),
            ]);
          }
          return request.method == 'GET' ? json(existing) : json({});
        });
        await http.runWithClient(() async {
          await tester.pumpWidget(
            const MaterialApp(home: PayrollRunPage(establishmentId: 'est-1')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Paie mensuelle'), findsOneWidget);

          await tester.tap(find.text('Ajouter un employé'));
          await tester.pumpAndSettle();
          expect(find.text('Mensuel X'), findsOneWidget);
          expect(find.text('Hebdo X'), findsNothing);
          expect(find.textContaining('F / mois'), findsOneWidget);
        }, () => srv);
      },
    );
  });
}
