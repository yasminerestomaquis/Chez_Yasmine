import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chez_yasmine/notifications/notifications_page.dart';

void main() {
  testWidgets('shows the app bar actions and an empty/error state without crashing', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NotificationsPage(establishmentId: 'est-1')));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.byIcon(Icons.campaign_outlined), findsOneWidget);
    expect(find.byIcon(Icons.inventory_outlined), findsOneWidget);
  });

  testWidgets('the broadcast dialog requires a title', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NotificationsPage(establishmentId: 'est-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.campaign_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Envoyer'));
    await tester.pump();

    expect(find.text('Titre requis'), findsOneWidget);
  });

  testWidgets('accepts a valid title past validation', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NotificationsPage(establishmentId: 'est-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.campaign_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Titre *'), 'Fermeture demain');
    await tester.tap(find.text('Envoyer'));
    await tester.pump();

    expect(find.text('Titre requis'), findsNothing);
  });
}
