import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/tables/floor_plan_page.dart';

void main() {
  // ApiClient lit Supabase.instance de façon synchrone dès la construction
  // des widgets de ce module — même configuration que les autres tests de
  // module (voir reports_page_test.dart).
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  testWidgets('shows an empty state without crashing when no backend is reachable in test', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: FloorPlanPage(establishmentId: 'est-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tables'), findsOneWidget);
    // Pas de backend en test : le chargement échoue, l'écran affiche son
    // propre état d'erreur avec un bouton Réessayer plutôt que de planter.
    expect(find.text('Réessayer'), findsOneWidget);
  });
}
