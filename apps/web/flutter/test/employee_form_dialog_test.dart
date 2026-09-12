import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/payroll/employee_form_dialog.dart';

void main() {
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
