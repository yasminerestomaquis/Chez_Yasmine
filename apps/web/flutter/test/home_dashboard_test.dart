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

  testWidgets(
    'still shows the module grid (Tables, Caisse...) when the summary/breakdown/unread calls all fail — '
    'no backend reachable in test is exactly the offline case this must not block (regression 2026-09-13)',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: HomeDashboard(
            establishmentId: 'est-1',
            establishmentName: 'Chez Yasmine',
            roleName: 'Propriétaire',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Avant correctif, une des 3 requêtes échouées (résumé, ventilation,
      // non-lues) faisait basculer tout l'écran sur "Impossible de joindre
      // l'API", masquant la grille de modules — plus aucun module accessible
      // hors ligne. `pumpAndSettle` attend la résolution de `_load()` : si la
      // régression réapparaît, ces tuiles ne seraient plus trouvées.
      expect(find.text('Tables'), findsWidgets);
      expect(find.text('Caisse'), findsWidgets);
      expect(find.text('Stock'), findsWidgets);
      expect(find.textContaining('Impossible de joindre l\'API'), findsNothing);
    },
  );
}
