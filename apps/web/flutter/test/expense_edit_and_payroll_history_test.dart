import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/expenses/expenses_form_tab.dart';
import 'package:chez_yasmine/payroll/payroll_history_page.dart';

/// Demande du 2026-10-05 : date de saisie + modification des dépenses ;
/// historique des paies (employés nommés) avec modification de la période et
/// des lignes.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  final sent = <http.Request>[];

  http.Response json(Object body) =>
      http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

  setUp(sent.clear);

  Map<String, dynamic> expense(String id, {String? payrollRunId, String category = 'Bouteilles de gaz'}) => {
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
            return json([expense('e1'), expense('e2', payrollRunId: 'run-1', category: 'Salaires')]);
          }
          return json(expense('e1'));
        });

    testWidgets('chaque dépense affiche sa date de saisie ; seule la dépense manuelle est modifiable', (tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ExpensesFormTab(establishmentId: 'est-1'))));
        await tester.pumpAndSettle();

        final expected = DateFormat('dd/MM/yyyy à HH:mm').format(DateTime.parse('2026-10-03T14:30:00.000Z').toLocal());
        expect(find.text('Gaz'), findsOneWidget);
        expect(find.textContaining('Saisie le $expected'), findsNWidgets(2));
        expect(find.byTooltip('Modifier'), findsOneWidget, reason: 'la dépense de paie n\'est pas modifiable ici');
      }, expensesServer);
    });

    testWidgets('Modifier : formulaire pré-rempli, enregistrement par PATCH avec les nouvelles valeurs', (tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ExpensesFormTab(establishmentId: 'est-1'))));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Modifier'));
        await tester.pumpAndSettle();

        expect(find.text('Modifier la dépense'), findsOneWidget);
        expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Libellé *')).controller!.text, 'Gaz');
        expect(tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Montant *')).controller!.text, '12500');
        expect(find.text('Date : 02/10/2026'), findsOneWidget);

        await tester.enterText(find.widgetWithText(TextFormField, 'Libellé *'), 'Gaz 12 kg');
        await tester.enterText(find.widgetWithText(TextFormField, 'Montant *'), '13000');
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
    });

    testWidgets('Modifier puis Annuler : aucune requête de modification', (tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ExpensesFormTab(establishmentId: 'est-1'))));
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
    Map<String, dynamic> line(String id, String last, String first, int base, {int advance = 0}) => {
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
        'expense': {'id': 'e9', 'amount': 55000, 'expenseDate': '2026-10-04T00:00:00.000Z'},
        'lines': [line('l1', 'Koffi', 'Awa', 30000), line('l2', 'Traoré', 'Moussa', 25000)],
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
      await tester.pumpWidget(const MaterialApp(home: PayrollHistoryPage(establishmentId: 'est-1')));
      await tester.pumpAndSettle();
    }

    testWidgets('liste toutes les paies, avec le nom de chaque employé ; une paie annulée n\'est pas modifiable', (tester) async {
      await http.runWithClient(() async {
        await openHistory(tester);

        expect(find.text('Koffi Awa'), findsOneWidget);
        expect(find.text('Traoré Moussa'), findsOneWidget);
        expect(find.text('Yao Jean'), findsOneWidget, reason: 'les paies annulées restent dans l\'historique');
        expect(find.text('Payée'), findsOneWidget);
        expect(find.text('Annulée'), findsOneWidget);
        expect(find.textContaining('Total : 55 000'), findsOneWidget);
        // Paie payée : période + 2 lignes modifiables ; paie annulée : rien.
        expect(find.byTooltip('Modifier la période'), findsOneWidget);
        expect(find.byTooltip('Modifier'), findsNWidgets(2));
      }, payrollServer);
    });

    testWidgets('modifier la ligne d\'un employé (paie déjà payée) : avertissement puis PATCH', (tester) async {
      await http.runWithClient(() async {
        await openHistory(tester);

        await tester.tap(find.byTooltip('Modifier').first);
        await tester.pumpAndSettle();
        expect(find.textContaining('déjà payée'), findsOneWidget);

        await tester.enterText(find.widgetWithText(TextFormField, 'Avance'), '2000');
        await tester.tap(find.text('Enregistrer'));
        await tester.pumpAndSettle();

        final patch = sent.singleWhere((r) => r.method == 'PATCH');
        expect(patch.url.path, endsWith('/payroll/runs/run-a/lines/l1'));
        final body = jsonDecode(patch.body) as Map<String, dynamic>;
        expect(body['advance'], 2000);
        expect(body['adjustment'], 0);
      }, payrollServer);
    });

    testWidgets('modifier la période : PATCH avec les deux dates', (tester) async {
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
  });
}
