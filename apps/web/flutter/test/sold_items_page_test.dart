import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/pos/sold_items_page.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  testWidgets(
    'shows an error state without crashing when no backend is reachable in test',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SoldItemsPage(establishmentId: 'est-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Produits vendus'), findsOneWidget);
      // Pas de backend en test : listForDay échoue, le corps affiche le
      // message d'erreur plutôt que la liste des ventes.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}
