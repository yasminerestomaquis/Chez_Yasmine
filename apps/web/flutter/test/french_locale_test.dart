import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/main.dart';
import 'package:chez_yasmine/sync/global_sync_context.dart';

/// Demande du 2026-10-08 : tous les calendriers (et composants Material) en
/// français — avant, « Mon, Oct 5 », « October 2026 », « Select date ».
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  testWidgets('l’application est en français : calendrier, sélecteur de période, heure', (
    tester,
  ) async {
    await tester.pumpWidget(const ChezYasmineApp());
    await tester.pump();
    final context = GlobalSyncContext.navigatorKey.currentContext!;

    expect(Localizations.localeOf(context).languageCode, 'fr');

    // Calendrier d'un jour (octobre 2026 : le 5 est un lundi).
    showDatePicker(
      context: context,
      initialDate: DateTime(2026, 10, 5),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'Date de début',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('octobre 2026'), findsWidgets);
    expect(find.textContaining('October'), findsNothing);
    expect(find.textContaining('Mon,'), findsNothing);
    expect(find.text('Annuler'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('OK'), findsOneWidget);
    // En-têtes de colonnes : lundi en premier (L M M J V S D).
    expect(find.text('L'), findsWidgets);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    // Sélecteur de période.
    showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(
        start: DateTime(2026, 10, 5),
        end: DateTime(2026, 10, 7),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('octobre'), findsWidgets);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Enregistrer'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // Sélecteur d'heure : 24 h, sans AM/PM.
    showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 15, minute: 30),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('AM'), findsNothing);
    expect(find.textContaining('PM'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
  });
}
