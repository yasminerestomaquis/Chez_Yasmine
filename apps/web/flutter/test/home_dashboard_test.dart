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

  testWidgets(
    'the "Date" label is a dropdown defaulting to "Aujourd\'hui", opening a menu with today\'s label (2026-09-14)',
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

      expect(find.text("Aujourd'hui"), findsWidgets);

      await tester.tap(find.text("Aujourd'hui").first);
      await tester.pumpAndSettle();

      // `DropdownButton` construit un IndexedStack de tous les items même
      // fermé (pour dimensionner le champ sur le plus large) — chaque
      // libellé apparaît donc en double une fois le menu ouvert : un de
      // plus qu'avant l'ouverture confirme que le menu s'est bien déployé.
      expect(find.text("Aujourd'hui"), findsNWidgets(2));
    },
  );

  testWidgets(
    'selecting a past date from the dropdown reloads and drops "aujourd\'hui" from the label (2026-09-14)',
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

      await tester.tap(find.text("Aujourd'hui").first);
      await tester.pumpAndSettle();

      // Même formatage que `_frenchDate` (privée à home_dashboard.dart),
      // recalculé ici pour retrouver le libellé du jour précédent sans
      // dépendre d'une date figée.
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      const weekdays = [
        'lundi',
        'mardi',
        'mercredi',
        'jeudi',
        'vendredi',
        'samedi',
        'dimanche',
      ];
      const months = [
        'janvier',
        'février',
        'mars',
        'avril',
        'mai',
        'juin',
        'juillet',
        'août',
        'septembre',
        'octobre',
        'novembre',
        'décembre',
      ];
      final weekday = weekdays[yesterday.weekday - 1];
      final weekdayCapitalized =
          weekday[0].toUpperCase() + weekday.substring(1);
      final yesterdayLabel =
          '$weekdayCapitalized ${yesterday.day} ${months[yesterday.month - 1]}';

      // Widget de l'option de menu ouvert (voir le commentaire du test
      // ci-dessus sur l'IndexedStack) : `.last` cible bien le menu déployé.
      await tester.tap(find.text(yesterdayLabel).last);
      await tester.pumpAndSettle();

      expect(find.text("Aujourd'hui"), findsNothing);
      expect(find.text(yesterdayLabel), findsWidgets);
    },
  );
}
