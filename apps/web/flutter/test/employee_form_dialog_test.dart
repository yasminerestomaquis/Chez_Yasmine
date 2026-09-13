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
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Poste *'),
      'Cuisinière',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Salaire hebdomadaire *'),
      '30000',
    );
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(find.textContaining('téléphone'), findsOneWidget);
  });
}
