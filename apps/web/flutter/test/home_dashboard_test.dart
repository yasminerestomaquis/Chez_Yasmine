import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/home/home_dashboard.dart';

void main() {
  // Voir graphiques_page_test.dart/reports_page_test.dart : ApiClient lit
  // Supabase.instance de façon synchrone dès la construction des widgets de
  // ce module (HomeDashboard appelle ReportsRepository dès son premier build).
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  testWidgets(
    'shows a sync/refresh button in the app bar, to the left of Notifications',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeDashboard(
            establishmentId: 'est-1',
            establishmentName: 'Chez Yasmine',
            roleName: 'Gérant',
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byTooltip('Synchroniser / actualiser l\'application'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.sync), findsOneWidget);

      final actionsRow = tester
          .widgetList<IconButton>(find.byType(IconButton))
          .toList();
      final syncIndex = actionsRow.indexWhere(
        (b) => (b.icon as Icon).icon == Icons.sync,
      );
      final notificationsIndex = actionsRow.indexWhere(
        (b) => (b.icon as Icon).icon == Icons.notifications_outlined,
      );
      expect(syncIndex, greaterThanOrEqualTo(0));
      expect(notificationsIndex, greaterThan(syncIndex));
    },
  );
}
