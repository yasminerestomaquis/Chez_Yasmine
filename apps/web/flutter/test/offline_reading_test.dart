import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/api/api_client.dart';
import 'package:chez_yasmine/customers/customers_page.dart';
import 'package:chez_yasmine/sync/sync_queue_service.dart';
import 'package:chez_yasmine/tables/floor_plan_page.dart';
import 'package:chez_yasmine/tables/table_order_page.dart';
import 'package:chez_yasmine/tables/tables_repository.dart';

String entry(Object data) => jsonEncode({'savedAt': '2026-10-03T08:15:00.000Z', 'data': data});

Map<String, dynamic> tableJson(String id, String name, String status, {int orders = 0, double? total}) => {
      'id': id,
      'name': name,
      'status': status,
      'openOrderCount': orders,
      'currentTotal': total,
    };

final orderJson = {
  'id': 'o1',
  'tableId': 't2',
  'status': 'open',
  'items': [
    {
      'id': 'i1',
      'productId': 'p1',
      'quantity': 2,
      'unitPrice': 500,
      'product': {'name': 'Celtia', 'category': <String, dynamic>{}},
    },
  ],
};

const catalogCache =
    '{"categories":[],"products":[{"id":"p1","name":"Celtia","categoryId":null,"salePrice":500,"stockQuantity":10,"status":"active"}]}';

/// Exécute le test avec un serveur injoignable : toute requête échoue comme
/// une coupure réseau, seule la copie locale peut répondre.
Future<void> withNoServer(Future<void> Function() body) =>
    http.runWithClient(body, () => MockClient((_) async => throw http.ClientException('offline')));

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  group('Plan de salle hors ligne', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'chez_yasmine_read_cache_est-1_tables': entry([
          tableJson('t1', 'Terrasse libre', 'free'),
          tableJson('t2', 'Salon occupé', 'occupied', orders: 1, total: 1000),
        ]),
        'chez_yasmine_read_cache_est-1_orders_t2': entry([orderJson]),
        'chez_yasmine_catalog_cache_est-1': catalogCache,
      });
    });

    testWidgets('affiche les tables de la copie locale avec le bandeau « données du… »', (tester) async {
      await withNoServer(() async {
        await tester.pumpWidget(const MaterialApp(home: FloorPlanPage(establishmentId: 'est-1', roleName: 'Gérant')));
        await tester.pumpAndSettle();

        expect(find.textContaining('Hors ligne — données du'), findsOneWidget);
        expect(find.text('Terrasse libre'), findsOneWidget);
        expect(find.text('Salon occupé'), findsOneWidget);
        expect(find.text('Actualiser'), findsOneWidget);
        expect(find.text('Réessayer'), findsNothing);
      });
    });

    testWidgets('une table libre s\'ouvre hors ligne sur l\'appareil, puis des articles s\'y ajoutent (phase 4)', (tester) async {
      await withNoServer(() async {
        await tester.pumpWidget(const MaterialApp(home: FloorPlanPage(establishmentId: 'est-1', roleName: 'Gérant')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Terrasse libre'));
        await tester.pumpAndSettle();
        expect(find.text('Ouvrir la table'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, '4');
        await tester.tap(find.widgetWithText(FilledButton, 'Ouvrir'));
        await tester.pumpAndSettle();

        // Arrive sur l'addition créée localement, vide, sous le bandeau hors ligne.
        expect(find.text('Addition'), findsOneWidget);
        expect(find.textContaining('Hors ligne — données du'), findsOneWidget);

        var queue = await SyncQueueService(ApiClient(), 'est-1').listPending();
        expect(queue.map((o) => o.entityType), ['order_open']);
        expect(queue.single.payload, {'tableId': 't1', 'guestCount': 4});

        // Un article du catalogue en copie locale s'ajoute à cette addition.
        await tester.tap(find.text('Celtia').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Celtia').first);
        await tester.pumpAndSettle();

        queue = await SyncQueueService(ApiClient(), 'est-1').listPending();
        expect(queue.map((o) => o.entityType), ['order_open', 'order_item_add', 'order_item_set']);
        expect(queue[1].payload['orderId'], queue[0].id, reason: 'l\'article vise l\'addition créée hors ligne');
        expect(queue[2].payload['expectedQuantity'], 1);
        expect(queue[2].payload['quantity'], 2);
        expect(find.textContaining('1 000'), findsWidgets, reason: '2 x 500 FCFA');
      });
    });

    testWidgets('créer une table est refusé hors ligne', (tester) async {
      await withNoServer(() async {
        await tester.pumpWidget(const MaterialApp(home: FloorPlanPage(establishmentId: 'est-1', roleName: 'Gérant')));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Nouvelle table'));
        await tester.pumpAndSettle();

        expect(find.textContaining('exige une connexion'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
      });
    });

    testWidgets('une table occupée s\'ouvre directement sur son addition en copie locale', (tester) async {
      await withNoServer(() async {
        await tester.pumpWidget(const MaterialApp(home: FloorPlanPage(establishmentId: 'est-1', roleName: 'Gérant')));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Salon occupé'));
        await tester.pumpAndSettle();

        expect(find.text('Addition'), findsOneWidget);
        expect(find.textContaining('Hors ligne — données du'), findsOneWidget);
        expect(find.text('Celtia'), findsWidgets);
      });
    });
  });

  group('Addition hors ligne', () {
    Widget page() => MaterialApp(
          home: TableOrderPage(
            repository: TablesRepository(ApiClient(), 'est-1'),
            establishmentId: 'est-1',
            roleName: 'Gérant',
            tableId: 't2',
          ),
        );

    testWidgets('affiche l\'addition et le catalogue de la copie locale, avec le bandeau', (tester) async {
      SharedPreferences.setMockInitialValues({
        'chez_yasmine_read_cache_est-1_orders_t2': entry([orderJson]),
        'chez_yasmine_catalog_cache_est-1': catalogCache,
      });
      await withNoServer(() async {
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();

        expect(find.textContaining('Hors ligne — données du'), findsOneWidget);
        expect(find.text('Celtia'), findsWidgets);
        expect(find.textContaining('Aucune addition'), findsNothing);
      });
    });

    testWidgets('addition encaissée hors ligne (liste vide en copie) : message au lieu d\'un plantage', (tester) async {
      SharedPreferences.setMockInitialValues({
        'chez_yasmine_read_cache_est-1_orders_t2': entry([]),
        'chez_yasmine_catalog_cache_est-1': catalogCache,
      });
      await withNoServer(() async {
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();

        expect(find.text('Aucune addition ouverte sur cette table.'), findsOneWidget);
        expect(find.textContaining('Hors ligne — données du'), findsOneWidget);
      });
    });

    testWidgets('sans aucune copie locale : l\'erreur habituelle, pas de bandeau', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await withNoServer(() async {
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();

        expect(find.textContaining('Hors ligne — données du'), findsNothing);
        expect(find.byType(ErrorWidget), findsNothing);
      });
    });
  });

  group('Clients hors ligne', () {
    testWidgets('affiche la dernière liste de clients avec le bandeau', (tester) async {
      SharedPreferences.setMockInitialValues({
        'chez_yasmine_read_cache_est-1_customers': entry([
          {'id': 'c1', 'name': 'Kouassi Jean', 'phone': '0102030405', 'creditBalance': 2500, 'creditLimit': 10000},
        ]),
      });
      await withNoServer(() async {
        await tester.pumpWidget(const MaterialApp(home: CustomersPage(establishmentId: 'est-1')));
        await tester.pumpAndSettle();

        expect(find.textContaining('Hors ligne — données du'), findsOneWidget);
        expect(find.text('Kouassi Jean'), findsOneWidget);
        expect(find.textContaining('2 500 FCFA'), findsOneWidget);
      });
    });

    testWidgets('créer un client hors ligne : message d\'erreur réseau au lieu d\'une exception non gérée', (tester) async {
      SharedPreferences.setMockInitialValues({
        'chez_yasmine_read_cache_est-1_customers': entry([
          {'id': 'c1', 'name': 'Kouassi Jean', 'phone': '', 'creditBalance': 0, 'creditLimit': 0},
        ]),
      });
      await withNoServer(() async {
        await tester.pumpWidget(const MaterialApp(home: CustomersPage(establishmentId: 'est-1')));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Nom'), 'Nouveau client');
        await tester.tap(find.text('Créer'));
        await tester.pumpAndSettle();

        expect(find.textContaining('client non créé'), findsOneWidget);
      });
    });
  });
}
