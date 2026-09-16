import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/users/permissions_dashboard_page.dart';

void main() {
  testWidgets(
    'shows the app bar title and an error state without crashing when no backend is reachable',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PermissionsDashboardPage(establishmentId: 'est-1'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Gestion des permissions'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    },
  );
}
