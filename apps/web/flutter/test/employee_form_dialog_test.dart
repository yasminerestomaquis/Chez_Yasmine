import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/payroll/employee_form_dialog.dart';
import 'package:chez_yasmine/payroll/employee_models.dart';

void main() {
  testWidgets(
    'pre-fills fields and shows the edit title when given an existing employee',
    (tester) async {
      final employee = Employee(
        id: 'emp-1',
        lastName: 'Koffi',
        firstName: 'Awa',
        phone: '0708091011',
        position: 'Cuisinière',
        hireDate: DateTime(2025, 1, 1),
        weeklySalary: 45000,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    showEmployeeFormDialog(context, initial: employee),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text("Modifier l'employé"), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Nom *'), findsOneWidget);
      expect(find.text('Koffi'), findsOneWidget);
      expect(find.text('Awa'), findsOneWidget);
      expect(find.text('0708091011'), findsOneWidget);
      expect(find.text('45000'), findsOneWidget);
    },
  );

  testWidgets('rejects submit with an invalid Côte d\'Ivoire phone number', (
    tester,
  ) async {
    // ignore: unused_local_variable
    late Future<Map<String, dynamic>?> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => result = showEmployeeFormDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nom *'),
      'Koffi',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Prénoms *'),
      'Awa',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Téléphone *'),
      '123',
    );
    await tester.ensureVisible(find.text('Poste *'));
    await tester.tap(find.text('Poste *'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Serveur').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Salaire hebdomadaire *'),
      '30000',
    );
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(find.textContaining('téléphone'), findsOneWidget);
  });

  Widget opener(void Function(BuildContext) onOpen) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => onOpen(context),
          child: const Text('open'),
        ),
      ),
    ),
  );

  testWidgets(
    'Poste est une liste déroulante alimentée par les rôles fournis',
    (tester) async {
      await tester.pumpWidget(
        opener(
          (context) => showEmployeeFormDialog(
            context,
            positions: ['Caissier', 'Gérant', 'Serveur'],
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextFormField, 'Poste *'),
        findsNothing,
        reason: 'plus de saisie libre',
      );
      await tester.ensureVisible(find.text('Poste *'));
      await tester.tap(find.text('Poste *'));
      await tester.pumpAndSettle();
      expect(find.text('Caissier'), findsOneWidget);
      expect(find.text('Gérant'), findsOneWidget);
      expect(find.text('Serveur'), findsOneWidget);
      expect(find.text('Magasinier'), findsNothing);
    },
  );

  testWidgets(
    'sans liste de rôles (hors ligne), les rôles système par défaut sont proposés',
    (tester) async {
      await tester.pumpWidget(
        opener((context) => showEmployeeFormDialog(context)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Poste *'));
      await tester.tap(find.text('Poste *'));
      await tester.pumpAndSettle();
      expect(find.text('Serveur'), findsOneWidget);
      expect(find.text('Caissier'), findsOneWidget);
    },
  );

  testWidgets(
    'le poste actuel d\'un employé reste proposé même s\'il n\'est plus un rôle',
    (tester) async {
      final employee = Employee(
        id: 'emp-1',
        lastName: 'Koffi',
        firstName: 'Awa',
        phone: '0708091011',
        position: 'Cuisinière',
        hireDate: DateTime(2025, 1, 1),
        weeklySalary: 45000,
      );
      await tester.pumpWidget(
        opener(
          (context) => showEmployeeFormDialog(
            context,
            initial: employee,
            positions: ['Serveur'],
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Le poste sélectionné est affiché dans le champ.
      expect(find.text('Cuisinière'), findsOneWidget);
    },
  );

  testWidgets(
    'type de salaire mensuel : libellé du montant et valeur renvoyée',
    (tester) async {
      Map<String, dynamic>? result;
      await tester.pumpWidget(
        opener(
          (context) async => result = await showEmployeeFormDialog(
            context,
            positions: ['Serveur'],
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextFormField, 'Salaire hebdomadaire *'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Type de salaire *'));
      await tester.tap(find.text('Type de salaire *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mensuel').last);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'Salaire mensuel *'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nom *'),
        'Koffi',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Prénoms *'),
        'Awa',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Téléphone *'),
        '0708091011',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Salaire mensuel *'),
        '150000',
      );
      await tester.ensureVisible(find.text('Poste *'));
      await tester.tap(find.text('Poste *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Serveur').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!['salaryType'], 'monthly');
      expect(result!['weeklySalary'], 150000.0);
      expect(result!['position'], 'Serveur');
    },
  );
}
