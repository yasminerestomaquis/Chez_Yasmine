import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/payroll/payroll_run_page.dart';

void main() {
  testWidgets('shows a period picker to prepare a new payroll run', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: PayrollRunPage(establishmentId: 'est-1')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Préparer'), findsWidgets);
  });
}
