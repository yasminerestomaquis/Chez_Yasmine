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

  MockClient backend() => MockClient((request) async {
    final path = request.url.path;
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
    if (path.endsWith('/summary')) {
      return json({
        'from': '2026-10-07T00:00:00.000Z',
        'to': '2026-10-07T23:59:59.999Z',
        'revenue': 54950,
        'salesCount': 25,
        'discountTotal': 0,
        'cogs': 0,
        'grossMargin': 0,
        'expenses': 0,
        'losses': 0,
        'netProfit': 0,
        'receivables': 0,
        'lowStockCount': 8,
        'topProducts': [],
        'productProfitability': [],
        'serverPerformance': [],
      });
    }
    if (path.endsWith('/unread-count')) return json(1);
    return json({});
  });

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

  testWidgets('Serveur : ni total des ventes, ni plats, ni commandes/alertes', (
    tester,
  ) async {
    await http.runWithClient(() async {
      await open(tester, size: const Size(360, 800), role: 'Serveur');

      expect(find.text("Total ventes aujourd'hui"), findsNothing);
      expect(find.text('Alertes stock'), findsNothing);
      expect(find.textContaining('Recettes plats'), findsNothing);
      expect(find.text('Plats - Espèces'), findsNothing);
      expect(find.textContaining('Recettes Gbêlê'), findsOneWidget);
      expect(find.byIcon(Icons.workspace_premium), findsNothing);
      expect(tester.takeException(), isNull);
    }, backend);
  });
}
