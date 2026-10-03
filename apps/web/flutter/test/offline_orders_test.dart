import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/api/api_client.dart';
import 'package:chez_yasmine/catalog/catalog_cache.dart';
import 'package:chez_yasmine/catalog/models.dart';
import 'package:chez_yasmine/common/read_cache.dart';
import 'package:chez_yasmine/sync/operation_summary.dart';
import 'package:chez_yasmine/sync/pending_operation.dart';
import 'package:chez_yasmine/sync/sync_queue_service.dart';
import 'package:chez_yasmine/tables/offline_orders.dart';
import 'package:chez_yasmine/tables/tables_models.dart';
import 'package:chez_yasmine/tables/tables_repository.dart';

Product product(
  String id,
  String name, {
  double? salePrice = 500,
  double? unitSalePrice,
  double? reference,
  bool casePricing = false,
}) =>
    Product(
      id: id,
      name: name,
      status: 'active',
      stockQuantity: 10,
      salePrice: salePrice,
      unitSalePrice: unitSalePrice,
      referenceSalePrice: reference,
      category: Category(id: 'c', name: 'Cat', hasCasePricing: casePricing),
    );

Map<String, dynamic> tableJson(String id, String status, {int orders = 0, double? total}) =>
    {'id': id, 'name': 'Table $id', 'status': status, 'openOrderCount': orders, 'currentTotal': total};

String entry(Object data) => jsonEncode({'savedAt': '2026-10-03T08:15:00.000Z', 'data': data});

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  final t0 = DateTime.utc(2026, 10, 3, 8, 15);

  group('resolveLocalLine (miroir de OrdersService.addItem)', () {
    test('prix fixe : prix catalogue et quantité demandée', () {
      final line = resolveLocalLine(product('p', 'Celtia'), quantity: 2);

      expect(line.quantity, 2);
      expect(line.unitPrice, 500);
      expect(line.sellAsUnit, isFalse);
    });

    test('prix fixe, vente à l\'unité demandée et possible : prix à l\'unité, mémorisé', () {
      final p = product('p', 'Heineken', salePrice: 2000, unitSalePrice: 700);

      final line = resolveLocalLine(p, quantity: 1, sellAsUnit: true);

      expect(line.unitPrice, 700);
      expect(line.sellAsUnit, isTrue);
    });

    test('vente à l\'unité demandée mais impossible (aucun prix à l\'unité) : tarif normal, pas d\'unité', () {
      final line = resolveLocalLine(product('p', 'Celtia'), quantity: 1, sellAsUnit: true);

      expect(line.unitPrice, 500);
      expect(line.sellAsUnit, isFalse);
    });

    test('prix de référence variable (Gbêlê, 3000 FCFA/L) : quantité déduite du montant, arrondie à 2 décimales', () {
      final gbele = product('g', 'Gbêlê', salePrice: null, reference: 3000);

      final hundred = resolveLocalLine(gbele, amountPaid: 100);
      final twoHundred = resolveLocalLine(gbele, amountPaid: 200);

      expect(hundred.quantity, 0.03);
      expect(hundred.unitPrice, closeTo(3333.33, 0.01));
      expect(twoHundred.quantity, 0.07);
      expect(twoHundred.unitPrice, closeTo(2857.14, 0.01));
      expect(hundred.quantity * hundred.unitPrice, closeTo(100, 0.0001), reason: 'le total reste le montant payé');
    });

    test('prix libre (Poulets, Poissons…) : prix et quantité saisis', () {
      final chicken = product('c', 'Poulet', salePrice: null);

      final line = resolveLocalLine(chicken, quantity: 2, unitPrice: 3500);

      expect(line.unitPrice, 3500);
      expect(line.quantity, 2);
    });

    test('données manquantes ou montant trop faible : ArgumentError, comme le refus du serveur', () {
      final gbele = product('g', 'Gbêlê', salePrice: null, reference: 3000);
      final chicken = product('c', 'Poulet', salePrice: null);

      expect(() => resolveLocalLine(chicken, quantity: 1), throwsArgumentError);
      expect(() => resolveLocalLine(gbele), throwsArgumentError);
      expect(() => resolveLocalLine(gbele, amountPaid: 1), throwsArgumentError);
      expect(() => resolveLocalLine(product('p', 'Celtia')), throwsArgumentError);
    });
  });

  group('OfflineOrders', () {
    late TablesRepository repository;
    late SyncQueueService queue;
    late OfflineOrders offline;
    var counter = 0;

    setUp(() {
      counter = 0;
      SharedPreferences.setMockInitialValues({
        'chez_yasmine_read_cache_est-1_tables': entry([tableJson('t1', 'free'), tableJson('t2', 'occupied', orders: 1, total: 0)]),
      });
      repository = TablesRepository(ApiClient(), 'est-1', cache: ReadCache('est-1', now: () => t0));
      queue = SyncQueueService(ApiClient(), 'est-1');
      offline = OfflineOrders(
        repository: repository,
        queue: queue,
        deviceId: () async => 'device-1',
        newId: () => '00000000-0000-4000-8000-${(++counter).toString().padLeft(12, '0')}',
        now: () => t0.add(Duration(seconds: counter)),
      );
    });

    Future<List<PendingOperation>> pending() => queue.listPending();

    test('openOrder : met `order_open` en file (l\'id de l\'opération est celui de l\'addition) et crée l\'addition localement', () async {
      final order = await offline.openOrder('t1', guestCount: 4);

      final ops = await pending();
      expect(ops.single.entityType, 'order_open');
      expect(ops.single.id, order.id);
      expect(ops.single.payload, {'tableId': 't1', 'guestCount': 4});
      expect(order.pendingSync, isTrue);
      final cached = await repository.cachedOrders('t1');
      expect(cached.single.id, order.id);
      expect(cached.single.pendingSync, isTrue);
    });

    test('openOrder : la table passe à « occupée » dans la copie locale, avec ses convives', () async {
      await offline.openOrder('t1', guestCount: 4);

      final tables = (await repository.loadTables()).value;
      final table = tables.firstWhere((t) => t.id == 't1');
      expect(table.status, 'occupied');
      expect(table.openOrderCount, 1);
      expect(table.guestCount, 4);
    });

    test('openOrder sur une table déjà occupée : addition supplémentaire (compteur incrémenté)', () async {
      final existing = OrderDetail(id: 'o-server', tableId: 't2', status: 'open', items: const []);
      await repository.writeLocalOrders('t2', [existing]);

      await offline.openOrder('t2');

      final tables = (await repository.loadTables()).value;
      expect(tables.firstWhere((t) => t.id == 't2').openOrderCount, 2);
      expect((await repository.cachedOrders('t2')).length, 2);
    });

    test('addItem : nouvelle ligne => `order_item_add` (id de ligne choisi ici) et ligne locale au bon prix', () async {
      final order = await offline.openOrder('t1');

      final updated = await offline.addItem('t1', order, product('p1', 'Celtia', casePricing: true), quantity: 2);

      final ops = await pending();
      expect(ops.map((o) => o.entityType), ['order_open', 'order_item_add']);
      final add = ops[1].payload;
      expect(add['orderId'], order.id);
      expect(add['productId'], 'p1');
      expect(add['productName'], 'Celtia');
      expect(add['quantity'], 2);
      expect(add['itemId'], updated.items.single.id);
      expect(updated.items.single.quantity, 2);
      expect(updated.items.single.unitPrice, 500);
      expect(updated.items.single.hasCasePricing, isTrue, reason: 'indispensable au champ N° de la commande à l\'encaissement');
      expect(updated.total, 1000);
    });

    test('addItem : même produit au même prix => fusion par `order_item_set` (quantité vue + quantité visée), comme le serveur', () async {
      final order = await offline.openOrder('t1');
      var current = await offline.addItem('t1', order, product('p1', 'Celtia'));

      current = await offline.addItem('t1', current, product('p1', 'Celtia'));

      final ops = await pending();
      expect(ops.map((o) => o.entityType), ['order_open', 'order_item_add', 'order_item_set']);
      expect(ops[2].payload['itemId'], current.items.single.id);
      expect(ops[2].payload['expectedQuantity'], 1);
      expect(ops[2].payload['quantity'], 2);
      expect(current.items, hasLength(1));
      expect(current.items.single.quantity, 2);
    });

    test('addItem : même produit à prix libre mais à un autre prix => deux lignes distinctes', () async {
      final chicken = product('c', 'Poulet', salePrice: null);
      final order = await offline.openOrder('t1');
      var current = await offline.addItem('t1', order, chicken, unitPrice: 3000);

      current = await offline.addItem('t1', current, chicken, unitPrice: 3500);

      expect(current.items.map((i) => i.unitPrice), [3000, 3500]);
      expect((await pending()).map((o) => o.entityType), ['order_open', 'order_item_add', 'order_item_add']);
    });

    test('addItem sur une ligne du serveur déjà présente dans la copie : `order_item_set` visant l\'id du serveur', () async {
      final serverLine = OrderItemDetail(id: 'item-server', productId: 'p1', productName: 'Celtia', quantity: 3, unitPrice: 500);
      final serverOrder = OrderDetail(id: 'o-server', tableId: 't2', status: 'open', items: [serverLine]);
      await repository.writeLocalOrders('t2', [serverOrder]);

      final updated = await offline.addItem('t2', serverOrder, product('p1', 'Celtia'));

      final op = (await pending()).single;
      expect(op.entityType, 'order_item_set');
      expect(op.payload['itemId'], 'item-server');
      expect(op.payload['expectedQuantity'], 3);
      expect(op.payload['quantity'], 4);
      expect(updated.items.single.quantity, 4);
    });

    test('addItem de Gbêlê : `amountPaid` est envoyé (jamais unitPrice) et la ligne locale porte litres et prix déduits', () async {
      final order = await offline.openOrder('t1');

      final updated = await offline.addItem(
        't1',
        order,
        product('g', 'Gbêlê', salePrice: null, reference: 3000),
        amountPaid: 200,
      );

      final payload = (await pending()).last.payload;
      expect(payload['amountPaid'], 200);
      expect(payload.containsKey('unitPrice'), isFalse);
      expect(updated.items.single.quantity, 0.07);
      expect(updated.items.single.referenceSalePrice, 3000);
    });

    test('setQuantity : `order_item_set` avec la quantité vue ; zéro ou moins retire la ligne', () async {
      final order = await offline.openOrder('t1');
      var current = await offline.addItem('t1', order, product('p1', 'Celtia'), quantity: 2);
      final item = current.items.single;

      current = await offline.setQuantity('t1', current, item, 5);
      expect(current.items.single.quantity, 5);
      var ops = await pending();
      expect(ops.last.entityType, 'order_item_set');
      expect(ops.last.payload['expectedQuantity'], 2);
      expect(ops.last.payload['quantity'], 5);

      current = await offline.setQuantity('t1', current, current.items.single, 0);
      expect(current.items, isEmpty);
      ops = await pending();
      expect(ops.last.entityType, 'order_item_remove');
      expect(ops.last.payload['expectedQuantity'], 5);
    });

    test('removeItem : `order_item_remove` avec la quantité vue ; les autres lignes restent', () async {
      final order = await offline.openOrder('t1');
      var current = await offline.addItem('t1', order, product('p1', 'Celtia'));
      current = await offline.addItem('t1', current, product('p2', 'Flag'));

      current = await offline.removeItem('t1', current, current.items.first);

      expect(current.items.map((i) => i.productName), ['Flag']);
      final op = (await pending()).last;
      expect(op.entityType, 'order_item_remove');
      expect(op.payload['productName'], 'Celtia');
    });

    test('chaque saisie met à jour le total et le compteur de la table dans la copie locale', () async {
      final order = await offline.openOrder('t1');
      await offline.addItem('t1', order, product('p1', 'Celtia'), quantity: 3);

      final table = (await repository.loadTables()).value.firstWhere((t) => t.id == 't1');

      expect(table.currentTotal, 1500);
      expect(table.openOrderCount, 1);
    });

    test('les opérations sont mises en file dans l\'ordre de saisie, chacune avec son heure', () async {
      final order = await offline.openOrder('t1');
      var current = await offline.addItem('t1', order, product('p1', 'Celtia'));
      current = await offline.addItem('t1', current, product('p1', 'Celtia'));
      await offline.removeItem('t1', current, current.items.single);

      final ops = await pending();
      expect(ops.map((o) => o.entityType), ['order_open', 'order_item_add', 'order_item_set', 'order_item_remove']);
      for (var i = 1; i < ops.length; i++) {
        expect(ops[i].createdAt.isAfter(ops[i - 1].createdAt), isTrue, reason: 'heure de saisie croissante');
      }
    });

    test('la copie locale garde la date du dernier vrai chargement (jamais « rafraîchie » par une saisie locale)', () async {
      await repository.writeLocalOrders('t2', [OrderDetail(id: 'o', tableId: 't2', status: 'open', items: const [])]);
      final before = (await repository.loadOpenOrders('t2')).cachedAt;
      final order = (await repository.cachedOrders('t2')).single;

      await OfflineOrders(repository: repository, queue: queue, deviceId: () async => 'd', now: () => DateTime.utc(2031))
          .addItem('t2', order, product('p1', 'Celtia'));

      expect((await repository.loadOpenOrders('t2')).cachedAt, before);
    });
  });

  group('TablesRepository avec des opérations de tables en attente', () {
    Map<String, dynamic> serverOrder(String id, String tableId) =>
        {'id': id, 'tableId': tableId, 'status': 'open', 'items': <Map<String, dynamic>>[]};

    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

    PendingOperation op(String id, String type, [Map<String, dynamic>? payload]) => PendingOperation(
          id: id,
          entityType: type,
          deviceId: 'd',
          payload: payload ?? {'tableId': 't1'},
          createdAt: DateTime.utc(2026, 10, 3, 8, 30),
        );

    SyncQueueService newQueue() => SyncQueueService(ApiClient(), 'est-1', refreshSession: ({bool force = false}) async {});

    TablesRepository repo(SyncQueueService queue, {bool online = true}) => TablesRepository(
          ApiClient(),
          'est-1',
          cache: ReadCache('est-1', now: () => t0),
          syncQueue: queue,
          isOnline: () async => online,
        );

    setUp(() => SharedPreferences.setMockInitialValues({
          'chez_yasmine_read_cache_est-1_orders_t1': entry([
            {'id': 'o-local', 'tableId': 't1', 'status': 'open', 'pendingSync': true, 'items': <Map<String, dynamic>>[]},
          ]),
        }));

    test('hors ligne : la copie locale, saisies comprises, est servie ; aucune requête n\'est tentée', () async {
      final queue = newQueue();
      await queue.enqueue(op('o-local', 'order_open'));
      var requests = 0;

      final result = await http.runWithClient(
        () => repo(queue, online: false).loadOpenOrders('t1'),
        () => MockClient((_) async {
          requests++;
          return json([serverOrder('o-server', 't1')]);
        }),
      );

      expect(requests, 0);
      expect(result.isStale, isTrue);
      expect(result.value.single.id, 'o-local');
      expect(result.value.single.pendingSync, isTrue);
    });

    test('en ligne : les saisies partent d\'abord, puis l\'état réel du serveur est lu', () async {
      final queue = newQueue();
      await queue.enqueue(op('o-local', 'order_open'));
      final calls = <String>[];

      final result = await http.runWithClient(
        () => repo(queue).loadOpenOrders('t1'),
        () => MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          if (request.method == 'POST') {
            return json([
              {'id': 'o-local', 'status': 'SYNCED'},
            ]);
          }
          return json([serverOrder('o-local', 't1')]);
        }),
      );

      expect(calls.first, endsWith('/sync'));
      expect(calls.last, endsWith('/tables/t1/orders'));
      expect(result.isStale, isFalse);
      expect(result.value.single.pendingSync, isFalse);
      expect(await queue.listPending(), isEmpty);
    });

    test('la synchro échoue (serveur injoignable) : la copie locale reste affichée, la lecture du serveur n\'est pas utilisée', () async {
      final queue = newQueue();
      await queue.enqueue(op('o-local', 'order_open'));

      final result = await http.runWithClient(
        () => repo(queue).loadOpenOrders('t1'),
        () => MockClient((_) async => throw http.ClientException('offline')),
      );

      expect(result.isStale, isTrue);
      expect(result.value.single.id, 'o-local');
      expect(await queue.listPending(), hasLength(1));
    });

    test('opérations restantes alors que le serveur répond : il ne remplace PAS la copie locale (pas de saisie en double)', () async {
      final queue = newQueue();
      await queue.enqueue(op('o-local', 'order_open'));
      var orderReads = 0;

      final result = await http.runWithClient(
        () => repo(queue).loadOpenOrders('t1'),
        () => MockClient((request) async {
          if (request.method == 'POST') return json({'message': 'Bad gateway'}, 502);
          orderReads++;
          return json([serverOrder('o-server', 't1')]);
        }),
      );

      expect(orderReads, 0);
      expect(result.value.single.id, 'o-local');
    });

    test('sans opération de table en attente : lecture normale du serveur', () async {
      final result = await http.runWithClient(
        () => repo(newQueue()).loadOpenOrders('t1'),
        () => MockClient((_) async => json([serverOrder('o-server', 't1')])),
      );

      expect(result.isStale, isFalse);
      expect(result.value.single.id, 'o-server');
    });

    test('listOpenOrdersForTable n\'écrase pas la copie locale tant que des saisies attendent', () async {
      final queue = newQueue();
      await queue.enqueue(op('o-local', 'order_open'));

      await http.runWithClient(
        () => repo(queue).listOpenOrdersForTable('t1'),
        () => MockClient((_) async => json([serverOrder('o-server', 't1')])),
      );

      expect((await repo(queue).cachedOrders('t1')).single.id, 'o-local');
    });

    test('un encaissement d\'addition en attente compte aussi : la lecture sert la copie locale', () async {
      final queue = newQueue();
      await queue.enqueue(op('sale-1', 'sale', {'orderId': 'o-local', 'items': []}));

      expect(await queue.hasPendingTableOperations(), isTrue);
    });

    test('une vente de Caisse (sans addition) ne compte pas', () async {
      final queue = newQueue();
      await queue.enqueue(op('sale-1', 'sale', {'items': []}));

      expect(await queue.hasPendingTableOperations(), isFalse);
    });

    test('le préchargement des additions est suspendu tant que des saisies attendent', () async {
      final queue = newQueue();
      await queue.enqueue(op('o-local', 'order_open'));
      TablesRepository.resetPrefetchThrottle();
      var requests = 0;
      final tables = [RestaurantTable(id: 't1', name: 'T1', status: 'occupied', openOrderCount: 1)];

      await http.runWithClient(
        () => repo(queue).prefetchOpenOrders(tables),
        () => MockClient((_) async {
          requests++;
          return json([serverOrder('o', 't1')]);
        }),
      );

      expect(requests, 0);
    });
  });

  group('SyncQueueService : verrou et signal de fin de synchro', () {
    PendingOperation op(String id) => PendingOperation(
          id: id,
          entityType: 'order_open',
          deviceId: 'd',
          payload: {'tableId': 't1'},
          createdAt: DateTime.utc(2026, 10, 3),
        );

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('deux synchronisations simultanées ne se chevauchent jamais : la seconde attend la première', () async {
      final queue = SyncQueueService(ApiClient(), 'est-1', refreshSession: ({bool force = false}) async {});
      await queue.enqueue(op('a'));
      var inFlight = 0;
      var peak = 0;
      var posts = 0;

      final results = await http.runWithClient(
        () => Future.wait([queue.syncAll(), queue.syncAll()]),
        () => MockClient((request) async {
          posts++;
          inFlight++;
          if (inFlight > peak) peak = inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          inFlight--;
          return http.Response(
            jsonEncode([
              {'id': 'a', 'status': 'SYNCED'},
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      expect(peak, 1);
      expect(posts, 1, reason: 'la seconde synchro trouve la file déjà vidée');
      expect(results.map((r) => r.synced).toList(), [1, 0]);
    });

    test('une erreur de la première synchro n\'empêche pas la suivante', () async {
      final queue = SyncQueueService(ApiClient(), 'est-1', refreshSession: ({bool force = false}) async {});
      await queue.enqueue(op('a'));
      var attempt = 0;

      final outcome = await http.runWithClient(() async {
        final first = queue.syncAll().then<Object>((r) => r, onError: (Object e) => e);
        final second = queue.syncAll();
        return [await first, await second];
      }, () => MockClient((_) async {
        attempt++;
        if (attempt == 1) throw http.ClientException('offline');
        return http.Response(
          jsonEncode([
            {'id': 'a', 'status': 'SYNCED'},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }));

      expect(outcome[0], isA<http.ClientException>());
      expect((outcome[1] as SyncResult).synced, 1);
    });

    test('syncCompleted est incrémenté quand quelque chose est parti, jamais pour une file vide', () async {
      final queue = SyncQueueService(ApiClient(), 'est-1', refreshSession: ({bool force = false}) async {});
      final before = SyncQueueService.syncCompleted.value;

      await queue.syncAll();
      expect(SyncQueueService.syncCompleted.value, before);

      await queue.enqueue(op('a'));
      await http.runWithClient(
        queue.syncAll,
        () => MockClient((_) async => http.Response(
              jsonEncode([
                {'id': 'a', 'status': 'SYNCED'},
              ]),
              200,
              headers: {'content-type': 'application/json'},
            )),
      );
      expect(SyncQueueService.syncCompleted.value, before + 1);
    });
  });

  group('describeOperation (opérations de tables)', () {
    PendingOperation op(String type, Map<String, dynamic> payload) => PendingOperation(
          id: 'x',
          entityType: type,
          deviceId: 'd',
          payload: payload,
          createdAt: DateTime.utc(2026, 10, 3),
        );

    test('libellés lisibles, avec le nom du produit et les quantités vue → visée', () {
      expect(describeOperation(op('order_open', {'tableId': 't1', 'guestCount': 4})), 'Ouverture de table (4 couverts)');
      expect(describeOperation(op('order_open', {'tableId': 't1'})), 'Ouverture de table');
      expect(describeOperation(op('order_item_add', {'productName': 'Celtia'})), 'Ajout à une addition — Celtia');
      expect(
        describeOperation(op('order_item_set', {'productName': 'Celtia', 'expectedQuantity': 2, 'quantity': 3})),
        'Quantité modifiée sur une addition — Celtia (2 → 3)',
      );
      expect(describeOperation(op('order_item_remove', {'productName': 'Celtia'})), 'Retrait d\'une addition — Celtia');
    });
  });

  group('CatalogCache : règles de prix conservées hors ligne', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('prix de référence, prix à l\'unité, drapeaux de catégorie et unité survivent à un aller-retour', () async {
      final cache = CatalogCache('est-1');
      final beers = Category(id: 'c1', name: 'Bières', hasCasePricing: true);
      final gbele = Product(
        id: 'g',
        name: 'Gbêlê',
        status: 'active',
        stockQuantity: 5,
        categoryId: 'c2',
        category: Category(id: 'c2', name: 'Locales', isBeverage: true),
        requiresPriceAtSale: true,
        referenceSalePrice: 3000,
        unit: 'L',
      );
      final heineken = Product(
        id: 'h',
        name: 'Heineken',
        status: 'active',
        stockQuantity: 24,
        categoryId: 'c1',
        salePrice: 2000,
        unitSalePrice: 700,
        minStock: 6,
        bottlesPerCase: 24,
      );

      await cache.save([beers], [gbele, heineken]);
      final (categories, products) = (await cache.load())!;

      final g = products.firstWhere((p) => p.id == 'g');
      expect(g.referenceSalePrice, 3000);
      expect(g.requiresPriceAtSale, isTrue);
      expect(g.isReferencePriced, isTrue, reason: 'sans cela, Gbêlê serait traité comme un produit à prix libre');
      expect(g.category?.isBeverage, isTrue);
      expect(g.unit, 'L');
      final h = products.firstWhere((p) => p.id == 'h');
      expect(h.unitSalePrice, 700);
      expect(h.minStock, 6);
      expect(h.bottlesPerCase, 24);
      expect(h.hasCasePricing, isTrue, reason: 'catégorie retrouvée par categoryId');
      expect(categories.single.hasCasePricing, isTrue);
    });

    test('un ancien cache (sans ces champs) reste lisible', () async {
      SharedPreferences.setMockInitialValues({
        'chez_yasmine_catalog_cache_est-1':
            '{"categories":[{"id":"c","name":"X"}],"products":[{"id":"p","name":"Old","categoryId":"c","salePrice":100,"stockQuantity":3,"status":"active"}]}',
      });

      final (categories, products) = (await CatalogCache('est-1').load())!;

      expect(products.single.referenceSalePrice, isNull);
      expect(products.single.category, isNull);
      expect(categories.single.hasCasePricing, isFalse);
    });
  });
}
