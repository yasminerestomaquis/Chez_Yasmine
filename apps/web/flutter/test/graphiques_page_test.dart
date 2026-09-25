import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/charts/graphiques_page.dart';

void main() {
  // Voir reports_page_test.dart pour le pourquoi de cette configuration :
  // ApiClient lit Supabase.instance de façon synchrone dès la construction
  // des widgets de ce module.
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  // Chaque onglet est une longue ListView de 5 graphiques — un viewport de
  // test haut évite de dépendre du scroll pour atteindre les derniers,
  // puisque ListView ne construit que ce qui est visible (voir
  // product_form_page_test.dart pour le même motif).
  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: GraphiquesPage(establishmentId: 'est-1')));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the Recettes/Bénéfices tabs, a year selector, and the five chart titles without crashing',
      (tester) async {
    await pumpPage(tester);

    expect(find.text('Graphiques'), findsOneWidget);
    expect(find.text('Recettes'), findsOneWidget);
    expect(find.text('Bénéfices'), findsOneWidget);
    expect(find.text('${DateTime.now().year}'), findsOneWidget);

    // Onglet Recettes actif par défaut : les 5 graphiques du sous-module,
    // plus "Recettes des semaines" (2026-09-25, Recettes uniquement).
    expect(find.text('Recettes journalières totales'), findsOneWidget);
    expect(find.text('Recettes journalières totales par catégorie'), findsOneWidget);
    expect(find.text('Recettes journalières totales par produit'), findsOneWidget);
    expect(find.text('Top recettes'), findsOneWidget);
    expect(find.text('Recettes mensuelles'), findsOneWidget);
    expect(find.text('Recettes des semaines'), findsOneWidget);
  });

  testWidgets(
    '"Recettes des semaines" only appears on the Recettes tab, with a week multi-select defaulting to all weeks (2026-09-25)',
    (tester) async {
      await pumpPage(tester);

      expect(find.text('Recettes des semaines'), findsOneWidget);
      expect(find.text('Toutes les semaines'), findsOneWidget);

      await tester.tap(find.text('Bénéfices'));
      await tester.pumpAndSettle();

      expect(find.text('Recettes des semaines'), findsNothing);
    },
  );

  testWidgets('switching to the Bénéfices tab shows its five chart titles without an unhandled error',
      (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Bénéfices'));
    await tester.pumpAndSettle();

    expect(find.text('Bénéfice net — journalier'), findsOneWidget);
    expect(find.text('Marge brute — journalière par catégorie'), findsOneWidget);
    expect(find.text('Marge brute — journalière par produit'), findsOneWidget);
    expect(find.text('Top marge brute (par produit)'), findsOneWidget);
    expect(find.text('Bénéfice net — mensuel'), findsOneWidget);
  });

  testWidgets(
    'the Bénéfices tab groups its charts into a "BÉNÉFICE NET" section (Total, Mensuel) and a "MARGE BRUTE" section (Par catégorie, Par produit, Top), in that order, unlike Recettes which stays flat',
    (tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('Bénéfices'));
      await tester.pumpAndSettle();

      expect(find.text('BÉNÉFICE NET'), findsOneWidget);
      expect(find.text('MARGE BRUTE'), findsOneWidget);

      // BÉNÉFICE NET doit apparaître avant "Bénéfice net — journalier",
      // qui doit apparaître avant MARGE BRUTE, qui doit apparaître avant
      // "Marge brute — journalière par catégorie".
      final netHeaderY = tester.getTopLeft(find.text('BÉNÉFICE NET')).dy;
      final dailyTotalY = tester.getTopLeft(find.text('Bénéfice net — journalier')).dy;
      final grossHeaderY = tester.getTopLeft(find.text('MARGE BRUTE')).dy;
      final byCategoryY = tester.getTopLeft(find.text('Marge brute — journalière par catégorie')).dy;
      expect(netHeaderY, lessThan(dailyTotalY));
      expect(dailyTotalY, lessThan(grossHeaderY));
      expect(grossHeaderY, lessThan(byCategoryY));

      // Recettes n'a pas cette dualité net/brut : pas d'en-tête de section.
      await tester.tap(find.text('Recettes'));
      await tester.pumpAndSettle();
      expect(find.text('BÉNÉFICE NET'), findsNothing);
      expect(find.text('MARGE BRUTE'), findsNothing);
    },
  );

  testWidgets('changing the year filter rebuilds both tabs without an unhandled error', (tester) async {
    await pumpPage(tester);

    final previousYear = DateTime.now().year - 1;
    await tester.tap(find.text('${DateTime.now().year}'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$previousYear').last);
    await tester.pumpAndSettle();

    expect(find.text('Recettes journalières totales'), findsOneWidget);
  });

  testWidgets('switching to the Stock tab shows its header and lot-detail chrome without an unhandled error',
      (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Stock'));
    await tester.pumpAndSettle();

    // Pas de backend dans ce test : CatalogRepository.listProducts() échoue,
    // donc aucun produit à proposer — même stratégie que les filtres
    // catégorie/produit de MetricChartsTab dans ce fichier.
    expect(find.text('Détail d\'un produit'), findsOneWidget);
    expect(find.text('Voir tous les lots →'), findsOneWidget);
    expect(find.text('Aucun produit au catalogue'), findsOneWidget);
  });

  testWidgets('switching to the Dépenses tab shows its four chart titles (no "par produit") without an unhandled error',
      (tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('Dépenses'));
    await tester.pumpAndSettle();

    expect(find.text('Dépenses journalières totales'), findsOneWidget);
    expect(find.text('Dépenses journalières totales par catégorie'), findsOneWidget);
    expect(find.text('Top dépenses'), findsOneWidget);
    expect(find.text('Dépenses mensuelles'), findsOneWidget);
    // Contrairement à Recettes/Bénéfices, pas de graphique "par produit" —
    // une dépense n'est rattachée à aucun produit.
    expect(find.textContaining('par produit'), findsNothing);
  });

  testWidgets(
    'the Dépenses category filter offers the predefined categories as a multi-select, with a "Toutes" reset chip',
    (tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('Dépenses'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilterChip, 'Toutes'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Loyer'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Bouteilles de gaz'), findsOneWidget);
    },
  );

  testWidgets(
    'the "Repas" export button only appears on the Bénéfices tab (2026-09-25)',
    (tester) async {
      await pumpPage(tester);

      // Onglet Recettes actif par défaut : le bouton ne doit pas apparaître.
      expect(find.byTooltip('Repas (listing, export PDF)'), findsNothing);

      await tester.tap(find.text('Bénéfices'));
      await tester.pumpAndSettle();

      // Échec réseau (flutter_test) : `_permissions` retombe sur
      // `allChartPermissions`, qui inclut `charts.profit_meals_listing` —
      // contrairement à StockPage/ReportsPage (repli sur l'ensemble vide),
      // ce module affiche tout par défaut et laisse le serveur refuser ce
      // qui n'est pas accordé (voir la doc de `_permissions`).
      expect(find.byTooltip('Repas (listing, export PDF)'), findsOneWidget);

      await tester.tap(find.text('Stock'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Repas (listing, export PDF)'), findsNothing);
    },
  );
}
