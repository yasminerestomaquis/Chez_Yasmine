import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/api/api_client.dart';
import 'package:chez_yasmine/tables/table_order_page.dart';
import 'package:chez_yasmine/tables/tables_repository.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  testWidgets('shows an error state without crashing when no backend is reachable in test', (tester) async {
    final repository = TablesRepository(ApiClient(), 'est-1');
    await tester.pumpWidget(
      MaterialApp(
        home: TableOrderPage(
          repository: repository,
          establishmentId: 'est-1',
          tableId: 'table-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Addition'), findsOneWidget);
    // Pas de backend en test : listOpenOrdersForTable échoue, le corps
    // affiche le message d'erreur plutôt qu'un panier/une grille.
    expect(find.byIcon(Icons.add_box_outlined), findsOneWidget);
  });
}
