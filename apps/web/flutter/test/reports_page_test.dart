import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/reports/reports_page.dart';

void main() {
  // Needed so ApiClient's synchronous Supabase.instance lookup (evaluated
  // before the first `await`, e.g. when a tap handler rebuilds `_future`
  // outside a try/catch) doesn't throw before ever reaching the network
  // call — see stock_movement_dialog_test.dart for the same setup.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  testWidgets('shows a period selector with the four periods and no crash on load failure', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReportsPage(establishmentId: 'est-1')));
    await tester.pumpAndSettle();

    expect(find.text('Jour'), findsOneWidget);
    expect(find.text('Semaine'), findsOneWidget);
    expect(find.text('Mois'), findsOneWidget);
    expect(find.text('Année'), findsOneWidget);
  });

  testWidgets('switching period selects the new segment and reloads without an unhandled error', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReportsPage(establishmentId: 'est-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mois'));
    // flutter_test's HttpOverrides answers every real request with an
    // instant 400 (see _MockHttpOverrides in flutter_test) — instant enough
    // that, without ReportsPage's `future.ignore()`, this future could
    // reject before FutureBuilder ever subscribes to it on rebuild, which
    // the Dart runtime reports as an unhandled error and fails the test even
    // though the UI itself would have handled it fine. pumpAndSettle here
    // (rather than a single pump) is deliberate: it's what actually
    // exercises that race.
    await tester.pumpAndSettle();

    final button = tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
    expect(button.selected, {'month'});
  });
}
