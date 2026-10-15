import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/home/home_dashboard.dart';

/// Demande du 2026-10-07 : nouvelle interface du tableau de bord (bandeau
/// d'accueil, cartes dégradées, tuiles colorées). Ces tests rendent l'écran
/// AVEC des données — les autres tests de l'accueil n'ont aucun serveur — et
/// vérifient surtout l'absence de débordement sur téléphone étroit comme sur
/// grand écran.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
    );
  });

  http.Response json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  const allHome = [
    'home.total_sales',
    'home.cash',
    'home.mobile_money',
    'home.orders',
    'home.stock_alerts',
    'home.revenue_beverages',
    'home.revenue_gbele',
    'home.revenue_plats',
    'home.detail_beverages_cash',
    'home.detail_beverages_mobile',
    'home.detail_gbele_cash',
    'home.detail_gbele_mobile',
    'home.detail_plats_cash',
    'home.detail_plats_mobile',
  ];

  // [permissions] : rubriques `home.*` accordées (toutes par défaut) ;
  // [permissionsFail] : la lecture des droits échoue (repli sur les défauts par rôle).
  MockClient makeBackend({List<String> permissions = allHome, bool permissionsFail = false}) => MockClient((request) async {
    final path = request.url.path;
    if (path.endsWith('/home-permissions')) {
      return permissionsFail ? http.Response('indisponible', 503) : json({'permissions': permissions});
    }
    if (path.endsWith('/payment-category-breakdown')) {
      return json({
        'totalRevenue': 54950,
        'cashRevenue': 48250,
        'mobileMoneyRevenue': 6700,
        'boissonsSansGbeleRevenue': 12500,
        'gbeleRevenue': 1000,
        'platsRevenue': 41450,
        'boissonsSansGbeleCash': 11300,
        'boissonsSansGbeleMobileMoney': 1200,
        'gbeleCash': 1000,
        'gbeleMobileMoney': 0,
        'platsCash': 35950,
        'platsMobileMoney': 5500,
      });
    }
    if (path.endsWith('/home-summary')) {
      return json({'salesCount': 25, 'lowStockCount': 8});
    }
    if (path.endsWith('/unread-count')) return json(1);
    return json({});
  });

  MockClient backend() => makeBackend();

  Future<void> open(
    WidgetTester tester, {
    required Size size,
    String role = 'Super Administrateur',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeDashboard(
          establishmentId: 'est-1',
          establishmentName: 'Chez Yasmine',
          roleName: role,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(360, 800), Size(412, 900), Size(1200, 900)]) {
    testWidgets('affiche toutes les cartes sans débordement à ${size.width.toInt()} px', (
      tester,
    ) async {
      await http.runWithClient(() async {
        await open(tester, size: size);

        expect(find.text('Bonjour, Super Administrateur'), findsOneWidget);
        expect(find.byIcon(Icons.workspace_premium), findsOneWidget);
        expect(find.text("Total ventes aujourd'hui"), findsOneWidget);
        expect(find.text('54 950 F'), findsOneWidget);
        expect(find.text('Espèces'), findsOneWidget);
        expect(find.text('Mobile Money'), findsOneWidget);
        expect(find.text('48 250 F'), findsOneWidget);
        expect(find.text("Commandes aujourd'hui"), findsOneWidget);
        expect(find.text('25'), findsOneWidget);
        expect(find.text('Alertes stock'), findsOneWidget);
        expect(find.text('RECETTES DU JOUR'), findsOneWidget);
        expect(find.text('DÉTAIL PAR MODE DE PAIEMENT'), findsOneWidget);
        expect(find.text('Boissons sans Gbêlê - Mobile Money'), findsOneWidget);
        expect(find.text('Plats - Espèces'), findsOneWidget);
        expect(find.text('ACTIONS RAPIDES'), findsOneWidget);
        expect(find.text('OPÉRATIONS'), findsOneWidget);
        // Régression 2026-10-07 : « Espèces » / « Mobile Money » s'écrivaient
        // à la verticale (une lettre par ligne) sur téléphone — chaque
        // désignation doit tenir sur une ou deux lignes au plus.
        for (final label in ['Espèces', 'Mobile Money']) {
          expect(
            tester.getSize(find.text(label)).height,
            lessThan(2.5 * 13 * 1.25),
            reason: '« $label » ne doit pas être écrasé en colonne étroite',
          );
        }
        // Aucun débordement (RenderFlex overflow) levé pendant le rendu.
        expect(tester.takeException(), isNull);

        // Le bas de page (modules de gestion/pilotage) reste atteignable.
        await tester.scrollUntilVisible(
          find.text('PILOTAGE'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('PILOTAGE'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, backend);
    });
  }

  testWidgets('la barre de navigation du bas est conservée (Accueil, Caisse, Action, Achats, Menu)', (
    tester,
  ) async {
    await http.runWithClient(() async {
      await open(tester, size: const Size(360, 800));

      final bar = tester.widget<BottomNavigationBar>(
        find.byType(BottomNavigationBar),
      );
      expect(bar.items.map((i) => i.label), [
        'Accueil',
        'Caisse',
        'Action',
        'Achats',
        'Menu',
      ]);
      expect(bar.currentIndex, 0);
    }, backend);
  });

  group('droits d’affichage de l’Accueil (home.*, 2026-10-15)', () {
    const serveur = [
      'home.revenue_beverages',
      'home.revenue_gbele',
      'home.detail_beverages_cash',
      'home.detail_beverages_mobile',
      'home.detail_gbele_cash',
      'home.detail_gbele_mobile',
    ];

    testWidgets('droits par défaut du Serveur : seules les recettes boissons sans Gbêlê / Gbêlê', (tester) async {
      await http.runWithClient(() async {
        await open(tester, size: const Size(360, 800), role: 'Serveur');

        expect(find.text("Total ventes aujourd'hui"), findsNothing);
        expect(find.text('Espèces'), findsNothing);
        expect(find.text('Mobile Money'), findsNothing);
        expect(find.text('Alertes stock'), findsNothing);
        expect(find.textContaining('Recettes plats'), findsNothing);
        expect(find.text('Plats - Espèces'), findsNothing);
        expect(find.textContaining('Recettes boissons sans Gbêlê'), findsOneWidget);
        expect(find.textContaining('Recettes Gbêlê'), findsOneWidget);
        expect(find.text('Gbêlê - Espèces'), findsOneWidget);
        expect(find.byIcon(Icons.workspace_premium), findsNothing);
        expect(tester.takeException(), isNull);
      }, () => makeBackend(permissions: serveur));
    });

    testWidgets('une seule rubrique accordée : sa carte seule, sans les autres sections', (tester) async {
      await http.runWithClient(() async {
        await open(tester, size: const Size(360, 800), role: 'Gérant');

        expect(find.text('Espèces'), findsOneWidget);
        expect(find.text('48 250 F'), findsOneWidget);
        expect(find.text('Mobile Money'), findsNothing);
        expect(find.text("Total ventes aujourd'hui"), findsNothing);
        expect(find.text('RECETTES DU JOUR'), findsNothing);
        expect(find.text('DÉTAIL PAR MODE DE PAIEMENT'), findsNothing);
        expect(find.text("Commandes aujourd'hui"), findsNothing);
        // La navigation reste intacte.
        expect(find.byType(BottomNavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, () => makeBackend(permissions: ['home.cash']));
    });

    testWidgets('Commandes et Alertes stock suivent leurs propres rubriques', (tester) async {
      await http.runWithClient(() async {
        await open(tester, size: const Size(360, 800));

        expect(find.text("Commandes aujourd'hui"), findsNothing);
        expect(find.text('Alertes stock'), findsOneWidget);
        expect(find.text('8'), findsOneWidget);
      }, () => makeBackend(permissions: ['home.stock_alerts']));
    });

    testWidgets('aucune rubrique accordée : aucune carte, mais le bandeau et les modules restent', (tester) async {
      await http.runWithClient(() async {
        await open(tester, size: const Size(360, 800));

        expect(find.text('Espèces'), findsNothing);
        expect(find.text('RECETTES DU JOUR'), findsNothing);
        expect(find.text('Bonjour, Super Administrateur'), findsOneWidget);
        expect(find.text('ACTIONS RAPIDES'), findsOneWidget);
        expect(find.text('OPÉRATIONS'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }, () => makeBackend(permissions: const []));
    });

    testWidgets('droits illisibles (hors ligne) : repli sur les défauts historiques par rôle', (tester) async {
      await http.runWithClient(() async {
        await open(tester, size: const Size(360, 800), role: 'Serveur');
        expect(find.text('Espèces'), findsNothing);
        expect(find.textContaining('Recettes plats'), findsNothing);
        expect(find.textContaining('Recettes Gbêlê'), findsOneWidget);
      }, () => makeBackend(permissionsFail: true));

      await http.runWithClient(() async {
        await open(tester, size: const Size(360, 800), role: 'Gérant');
        expect(find.text('Espèces'), findsOneWidget);
        expect(find.textContaining('Recettes plats'), findsOneWidget);
      }, () => makeBackend(permissionsFail: true));
    });
  });
}
