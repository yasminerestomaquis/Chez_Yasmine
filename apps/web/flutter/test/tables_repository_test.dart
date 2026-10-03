import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/api/api_client.dart';
import 'package:chez_yasmine/common/read_cache.dart';
import 'package:chez_yasmine/customers/customers_repository.dart';
import 'package:chez_yasmine/tables/tables_repository.dart';

Map<String, dynamic> tableJson(String id, {String status = 'occupied', int orders = 1, double? total = 1000, String? zone}) => {
      'id': id,
      'name': 'Table $id',
      'zone': zone,
      'status': status,
      'guestCount': 3,
      'currentTotal': total,
      'openOrderCount': orders,
    };

Map<String, dynamic> orderJson(String id, String tableId, {double quantity = 2, double unitPrice = 500}) => {
      'id': id,
      'tableId': tableId,
      'status': 'open',
      'items': [
        {
          'id': 'item-$id',
          'productId': 'p1',
          'quantity': quantity,
          'unitPrice': unitPrice,
          'product': {'name': 'Celtia', 'category': {'hasCasePricing': true}},
        },
      ],
    };

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Future<T> online<T>(Future<T> Function() body, http.Response Function(http.Request) handler) =>
    http.runWithClient(body, () => MockClient((request) async => handler(request)));

Future<T> offline<T>(Future<T> Function() body) =>
    http.runWithClient(body, () => MockClient((_) async => throw http.ClientException('offline')));

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  final t0 = DateTime.utc(2026, 10, 3, 8, 15);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TablesRepository.resetPrefetchThrottle();
  });

  TablesRepository repo({DateTime? savedAt}) =>
      TablesRepository(ApiClient(), 'est-1', cache: ReadCache('est-1', now: () => savedAt ?? t0));

  group('TablesRepository.loadTables', () {
    test('en ligne : tables fraîches et copie enregistrée', () async {
      final result = await online(() => repo().loadTables(), (_) => json([tableJson('t1'), tableJson('t2', status: 'free', orders: 0, total: null)]));

      expect(result.isStale, isFalse);
      expect(result.value.map((t) => t.name), ['Table t1', 'Table t2']);
    });

    test('hors ligne : dernière copie servie avec sa date, statuts et totaux conservés', () async {
      await online(() => repo().loadTables(), (_) => json([tableJson('t1', total: 2500)]));

      final result = await offline(() => repo(savedAt: DateTime.utc(2030)).loadTables());

      expect(result.isStale, isTrue);
      expect(result.cachedAt, t0, reason: 'la date est celle de la copie, pas du moment de la lecture');
      expect(result.value.single.currentTotal, 2500);
      expect(result.value.single.status, 'occupied');
    });

    test('hors ligne sans aucune copie : l\'erreur réseau remonte', () async {
      await expectLater(offline(() => repo().loadTables()), throwsA(isA<http.ClientException>()));
    });
  });

  group('TablesRepository.loadOpenOrders', () {
    test('hors ligne : l\'addition vue en ligne est relisible, lignes comprises', () async {
      await online(() => repo().loadOpenOrders('t1'), (_) => json([orderJson('o1', 't1')]));

      final result = await offline(() => repo().loadOpenOrders('t1'));

      expect(result.isStale, isTrue);
      final order = result.value.single;
      expect(order.items.single.productName, 'Celtia');
      expect(order.items.single.hasCasePricing, isTrue);
      expect(order.total, 1000);
    });

    test('listOpenOrdersForTable enregistre aussi la copie (les ouvertures de table alimentent le cache)', () async {
      await online(() => repo().listOpenOrdersForTable('t1'), (_) => json([orderJson('o1', 't1')]));

      final result = await offline(() => repo().loadOpenOrders('t1'));

      expect(result.value.single.id, 'o1');
    });

    test('les copies de deux tables ne se mélangent pas', () async {
      await online(() => repo().loadOpenOrders('t1'), (_) => json([orderJson('o1', 't1')]));

      await expectLater(offline(() => repo().loadOpenOrders('t2')), throwsA(isA<http.ClientException>()));
    });
  });

  group('TablesRepository.prefetchOpenOrders', () {
    test('télécharge les additions des seules tables occupées', () async {
      final requested = <String>[];
      final tables = (await online(() => repo().loadTables(), (_) => json([
            tableJson('t1', orders: 2),
            tableJson('t2', status: 'free', orders: 0, total: null),
            tableJson('t3'),
          ])))
          .value;

      await online(() => repo().prefetchOpenOrders(tables), (request) {
        requested.add(request.url.path);
        return json([orderJson('o', 'x')]);
      });

      expect(requested.where((p) => p.endsWith('/orders')).length, 2);
      expect(requested.any((p) => p.contains('/tables/t2/')), isFalse);
      expect((await offline(() => repo().loadOpenOrders('t1'))).isStale, isTrue);
      expect((await offline(() => repo().loadOpenOrders('t3'))).value, isNotEmpty);
    });

    test('au plus 3 requêtes en parallèle', () async {
      var running = 0;
      var peak = 0;
      final tables = (await online(() => repo().loadTables(), (_) => json([for (var i = 0; i < 9; i++) tableJson('t$i')]))).value;

      await http.runWithClient(
        () => repo().prefetchOpenOrders(tables),
        () => MockClient((request) async {
          running++;
          if (running > peak) peak = running;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          running--;
          return json([orderJson('o', 'x')]);
        }),
      );

      expect(peak, lessThanOrEqualTo(3));
      expect(peak, greaterThan(1));
    });

    test('au plus une fois par minute et par établissement', () async {
      var calls = 0;
      final tables = (await online(() => repo().loadTables(), (_) => json([tableJson('t1')]))).value;
      http.Response handler(http.Request _) {
        calls++;
        return json([orderJson('o', 't1')]);
      }

      await online(() => repo().prefetchOpenOrders(tables), handler);
      await online(() => repo().prefetchOpenOrders(tables), handler);

      expect(calls, 1);
    });

    test('s\'arrête à la première coupure, sans exception', () async {
      var calls = 0;
      final tables = (await online(() => repo().loadTables(), (_) => json([for (var i = 0; i < 12; i++) tableJson('t$i')]))).value;

      await http.runWithClient(
        () => repo().prefetchOpenOrders(tables),
        () => MockClient((_) async {
          calls++;
          throw http.ClientException('offline');
        }),
      );

      expect(calls, lessThanOrEqualTo(3));
    });
  });

  group('TablesRepository.markOrderCheckedOutLocally', () {
    Future<void> seed({required List<Map<String, dynamic>> tables, required Map<String, List<Map<String, dynamic>>> orders}) async {
      await online(() => repo().loadTables(), (_) => json(tables));
      for (final entry in orders.entries) {
        await online(() => repo().loadOpenOrders(entry.key), (_) => json(entry.value));
      }
    }

    test('dernière addition encaissée : plus d\'addition ouverte et table libre', () async {
      await seed(tables: [tableJson('t1', total: 1000)], orders: {'t1': [orderJson('o1', 't1')]});
      final order = (await offline(() => repo().loadOpenOrders('t1'))).value.single;

      await repo(savedAt: DateTime.utc(2031)).markOrderCheckedOutLocally('t1', order);

      final orders = await offline(() => repo().loadOpenOrders('t1'));
      expect(orders.value, isEmpty);
      final table = (await offline(() => repo().loadTables())).value.single;
      expect(table.status, 'free');
      expect(table.openOrderCount, 0);
      expect(table.currentTotal, isNull);
      expect(table.guestCount, isNull);
    });

    test('une autre addition reste ouverte : la table reste occupée, total et compteur diminués', () async {
      await seed(
        tables: [tableJson('t1', orders: 2, total: 1800)],
        orders: {'t1': [orderJson('o1', 't1'), orderJson('o2', 't1', quantity: 1, unitPrice: 800)]},
      );
      final order = (await offline(() => repo().loadOpenOrders('t1'))).value.first;
      expect(order.total, 1000);

      await repo().markOrderCheckedOutLocally('t1', order);

      final orders = (await offline(() => repo().loadOpenOrders('t1'))).value;
      expect(orders.map((o) => o.id), ['o2']);
      final table = (await offline(() => repo().loadTables())).value.single;
      expect(table.status, 'occupied');
      expect(table.openOrderCount, 1);
      expect(table.currentTotal, 800);
    });

    test('la date de la copie reste celle du dernier vrai chargement', () async {
      await seed(tables: [tableJson('t1')], orders: {'t1': [orderJson('o1', 't1')]});
      final order = (await offline(() => repo().loadOpenOrders('t1'))).value.single;

      await repo(savedAt: DateTime.utc(2031)).markOrderCheckedOutLocally('t1', order);

      expect((await offline(() => repo().loadTables())).cachedAt, t0);
      expect((await offline(() => repo().loadOpenOrders('t1'))).cachedAt, t0);
    });

    test('sans copie locale, ne fait rien et ne plante pas', () async {
      final order = (await online(() => repo().loadOpenOrders('t1'), (_) => json([orderJson('o1', 't1')]))).value.single;
      SharedPreferences.setMockInitialValues({});

      await repo().markOrderCheckedOutLocally('t1', order);
    });
  });

  group('CustomersRepository.loadCustomers', () {
    Map<String, dynamic> customer(String id) => {
          'id': id,
          'name': 'Client $id',
          'phone': '0102030405',
          'creditBalance': 1500,
          'creditLimit': 5000,
        };

    CustomersRepository customers() => CustomersRepository(ApiClient(), 'est-1', cache: ReadCache('est-1', now: () => t0));

    test('hors ligne : la dernière liste est servie avec sa date, soldes compris', () async {
      await online(() => customers().loadCustomers(), (_) => json([customer('c1'), customer('c2')]));

      final result = await offline(() => customers().loadCustomers());

      expect(result.isStale, isTrue);
      expect(result.cachedAt, t0);
      expect(result.value.map((c) => c.name), ['Client c1', 'Client c2']);
      expect(result.value.first.creditBalance, 1500);
    });

    test('un refus du serveur (ex. permission) n\'est pas masqué par la copie', () async {
      await online(() => customers().loadCustomers(), (_) => json([customer('c1')]));

      await expectLater(
        online(() => customers().loadCustomers(), (_) => json({'message': 'Interdit'}, 403)),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
