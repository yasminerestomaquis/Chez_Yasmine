import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/users/users_page.dart';

void main() {
  testWidgets(
    '"Gestion des permissions" is only shown to Super Administrateur (2026-09-16)',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: UsersPage(establishmentId: 'est-1', roleName: 'Gérant'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.admin_panel_settings_outlined), findsNothing);
    },
  );

  testWidgets(
    '"Gestion des permissions" is shown to Super Administrateur',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: UsersPage(
            establishmentId: 'est-1',
            roleName: 'Super Administrateur',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.admin_panel_settings_outlined), findsOneWidget);
    },
  );
}
