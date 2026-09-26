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
    'the Date filter defaults to today and opens a multi-select dialog with a reset action (2026-09-20)',
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

      expect(find.text('Filtrer par date'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(7));
      expect(find.text('Réinitialiser'), findsOneWidget);
    },
  );

  testWidgets(
    'ticking several dates and applying relabels the filter with the day count (2026-09-20)',
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

      // Aujourd'hui est déjà coché : cocher la 2e ligne (hier) donne 2 jours.
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appliquer'));
      await tester.pumpAndSettle();

      expect(find.text('2 jours sélectionnés'), findsOneWidget);
      expect(find.text("Aujourd'hui"), findsNothing);
    },
  );

  testWidgets(
    'the Date filter offers a precise date+time interval option, on top of the default day selection (2026-09-26)',
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

      // Toujours 7 jours (comportement par défaut inchangé), plus l'option
      // d'intervalle précis en plus, jamais à la place.
      expect(find.byType(CheckboxListTile), findsNWidgets(7));
      expect(find.text('Définir un intervalle précis'), findsOneWidget);

      // Le dialogue est scrollable (`AlertDialog(scrollable: true)`, 7 jours
      // + séparateur + bouton dépassent souvent la hauteur visible) — fait
      // défiler jusqu'au bouton avant de le taper.
      await tester.ensureVisible(find.text('Définir un intervalle précis'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Définir un intervalle précis'));
      await tester.pumpAndSettle();

      expect(find.text('Choisir un intervalle'), findsOneWidget);
      expect(find.text('Du'), findsOneWidget);
      expect(find.text('Au'), findsOneWidget);

      // Tape "Du" -> calendrier natif (confirmé tel quel, aujourd'hui par
      // défaut) -> le sélecteur d'heure en 24h (menus "Heure"/"Minute",
      // jamais AM/PM) doit s'ouvrir ensuite, éditable au clavier ou par
      // sélection dans la liste (décisions utilisateur du 2026-09-26).
      await tester.tap(find.text('Du'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // `DropdownMenu` peut garder deux copies de son libellé flottant
      // pendant l'animation d'apparition (détail d'implémentation) — au
      // moins une de chaque suffit à confirmer que le sélecteur s'est ouvert.
      expect(find.text('Heure'), findsWidgets);
      expect(find.text('Minute'), findsWidgets);
      expect(find.textContaining('AM'), findsNothing);
      expect(find.textContaining('PM'), findsNothing);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // De retour sur "Choisir un intervalle", l'heure choisie a mis à jour "Du".
      expect(find.text('Choisir un intervalle'), findsOneWidget);
    },
  );
}
