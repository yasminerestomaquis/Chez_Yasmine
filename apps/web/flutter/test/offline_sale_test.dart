import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chez_yasmine/api/api_client.dart';
import 'package:chez_yasmine/catalog/catalog_cache.dart';
import 'package:chez_yasmine/catalog/models.dart';
import 'package:chez_yasmine/pos/receipt_page.dart';
import 'package:chez_yasmine/sync/failed_operations_dialog.dart';
import 'package:chez_yasmine/sync/offline_sale.dart';
import 'package:chez_yasmine/sync/operation_summary.dart';
import 'package:chez_yasmine/sync/pending_operation.dart';
import 'package:chez_yasmine/sync/sync_queue_service.dart';

Product product(String id, String name, {double stock = 10, double? salePrice = 500, double? reference}) => Product(
      id: id,
      name: name,
      status: 'active',
      stockQuantity: stock,
      salePrice: salePrice,
      referenceSalePrice: reference,
    );

PendingOperation operation(String type, Map<String, dynamic> payload, {String id = 'op-1', String? error}) =>
    PendingOperation(
      id: id,
      entityType: type,
      deviceId: 'd',
      payload: payload,
      createdAt: DateTime.utc(2026, 10, 2, 18, 30),
      lastError: error,
    );

void main() {
  group('stockUsedByLine (miroir de SalesService.create)', () {
    test('produit à prix fixe : la quantité demandée', () {
      expect(stockUsedByLine(product('p1', 'Celtia'), quantity: 3), 3);
    });

    test('prix de référence variable (Gbêlê, 3000 FCFA/L) : 100 F -> 0,03 L et 200 F -> 0,07 L (arrondi par vente)', () {
      final gbele = product('g', 'Gbêlê', salePrice: null, reference: 3000);
      expect(stockUsedByLine(gbele, quantity: 1, manualAmount: 100), 0.03);
      expect(stockUsedByLine(gbele, quantity: 1, manualAmount: 200), 0.07);
    });

    test('un prix fixe prime sur un montant saisi', () {
      final p = product('p', 'X', salePrice: 500, reference: 3000);
      expect(stockUsedByLine(p, quantity: 2, manualAmount: 100), 2);
    });
  });

  group('stockNeeded / stockShortages', () {
    test('agrège par produit, même quand il occupe plusieurs lignes', () {
      final needed = stockNeeded([
        (productId: 'p1', quantity: 2),
        (productId: 'p2', quantity: 1),
        (productId: 'p1', quantity: 3),
      ]);
      expect(needed, {'p1': 5, 'p2': 1});
    });

    test('signale les produits dont le stock local ne couvre pas la vente', () {
      final products = {'p1': product('p1', 'Celtia', stock: 4), 'p2': product('p2', 'Flag', stock: 9)};

      expect(stockShortages({'p1': 5, 'p2': 9}, products), ['Celtia']);
      expect(stockShortages({'p1': 4}, products), isEmpty, reason: 'stock exactement suffisant');
      expect(stockShortages({'inconnu': 1}, products), isEmpty);
    });
  });

  group('provisionalSale', () {
    test('établit un reçu cohérent à partir du panier et des paiements', () {
      final sale = provisionalSale(
        id: 'sale-12345678-xyz',
        createdAt: DateTime.utc(2026, 10, 2, 18, 30),
        lines: [
          ProvisionalLine(productId: 'p1', name: 'Celtia', quantity: 2, unitPrice: 500),
          ProvisionalLine(productId: 'p2', name: 'Flag', quantity: 1, unitPrice: 600),
        ],
        payments: [(method: 'cash', amount: 1600)],
        orderNumber: 7,
      );

      expect(sale.subtotal, 1600);
      expect(sale.total, 1600);
      expect(sale.discount, 0);
      expect(sale.items.map((i) => i.name), ['Celtia', 'Flag']);
      expect(sale.payments.single.amount, 1600);
      expect(sale.orderNumber, 7);
      expect(sale.id, 'sale-12345678-xyz');
    });
  });

  group('CatalogCache.applyStockDecrements', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('retire la quantité vendue du stock mis en cache, sans toucher aux autres produits', () async {
      final cache = CatalogCache('est-1');
      await cache.save([], [product('p1', 'Celtia', stock: 10), product('p2', 'Flag', stock: 5)]);

      await cache.applyStockDecrements({'p1': 3});
      final (_, products) = (await cache.load())!;

      expect(products.firstWhere((p) => p.id == 'p1').stockQuantity, 7);
      expect(products.firstWhere((p) => p.id == 'p2').stockQuantity, 5);
    });

    test('plusieurs ventes hors ligne successives se cumulent, jusqu\'à un stock négatif possible', () async {
      final cache = CatalogCache('est-1');
      await cache.save([], [product('p1', 'Celtia', stock: 2)]);

      await cache.applyStockDecrements({'p1': 1.5});
      await cache.applyStockDecrements({'p1': 1});
      final (_, products) = (await cache.load())!;

      expect(products.single.stockQuantity, -0.5);
    });

    test('sans catalogue en cache, ne fait rien', () async {
      await CatalogCache('est-1').applyStockDecrements({'p1': 1});
      expect(await CatalogCache('est-1').load(), isNull);
    });
  });

  group('describeOperation', () {
    test('vente et encaissement d\'addition', () {
      final payments = {
        'payments': [
          {'method': 'cash', 'amount': 1000},
          {'method': 'mobile_money', 'amount': 1500},
        ],
      };
      expect(describeOperation(operation('sale', payments)), 'Vente — 2 500 FCFA');
      expect(describeOperation(operation('sale', {...payments, 'orderId': 'o1'})), 'Encaissement d\'une addition — 2 500 FCFA');
    });

    test('les autres types d\'opération', () {
      expect(describeOperation(operation('stock_movement', {'type': 'out', 'quantity': 3})), 'Sortie de stock — quantité 3');
      expect(describeOperation(operation('stock_movement', {'type': 'adjustment', 'quantity': 1.5})), 'Correction de stock — quantité 1.5');
      expect(describeOperation(operation('expense', {'label': 'Eau', 'amount': 5000})), 'Dépense — Eau (5 000 FCFA)');
      expect(describeOperation(operation('loss', {'quantity': 2})), 'Perte — quantité 2');
      expect(describeOperation(operation('purchase', {'orderNumber': 12})), 'Commande d\'achat n°12');
      expect(describeOperation(operation('cash_closing', {'countedAmount': 45000})), 'Clôture de caisse — compté 45 000 FCFA');
    });
  });

  group('ReceiptPage provisoire', () {
    final sale = provisionalSale(
      id: 'sale-12345678',
      createdAt: DateTime.utc(2026, 10, 2, 18, 30),
      lines: [ProvisionalLine(productId: 'p1', name: 'Celtia', quantity: 2, unitPrice: 500)],
      payments: [(method: 'cash', amount: 1000)],
    );

    testWidgets('affiche le bandeau « reçu provisoire » hors ligne', (tester) async {
      await tester.pumpWidget(MaterialApp(home: ReceiptPage(sale: sale, provisional: true)));

      expect(find.textContaining('REÇU PROVISOIRE'), findsOneWidget);
      expect(find.textContaining('Celtia'), findsOneWidget);
    });

    testWidgets('pas de bandeau pour un reçu normal', (tester) async {
      await tester.pumpWidget(MaterialApp(home: ReceiptPage(sale: sale)));

      expect(find.textContaining('REÇU PROVISOIRE'), findsNothing);
    });
  });

  group('FailedOperationsDialog', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<SyncQueueService> queueWithOneFailure() async {
      final failed = operation(
        'sale',
        {
          'payments': [
            {'method': 'cash', 'amount': 1000},
          ],
        },
        id: 'refusee',
        error: 'Stock insuffisant pour Celtia',
      );
      // État laissé par une synchro dont le serveur a refusé cette vente.
      SharedPreferences.setMockInitialValues({'chez_yasmine_sync_failed_est-1': '[${_encode(failed)}]'});
      return SyncQueueService(ApiClient(), 'est-1');
    }

    Future<void> openDialog(WidgetTester tester, SyncQueueService queue, {VoidCallback? onRetry}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showFailedOperationsDialog(context, queue, onRetry: onRetry),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('liste l\'opération refusée avec son résumé, sa date de saisie et son motif', (tester) async {
      final queue = await tester.runAsync(queueWithOneFailure) as SyncQueueService;
      await openDialog(tester, queue);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();

      expect(find.text('Vente — 1 000 FCFA'), findsOneWidget);
      expect(find.textContaining('Stock insuffisant pour Celtia'), findsOneWidget);
      expect(find.textContaining('Saisie le'), findsOneWidget);
    });

    testWidgets('Réessayer remet l\'opération en file et prévient l\'appelant', (tester) async {
      final queue = await tester.runAsync(queueWithOneFailure) as SyncQueueService;
      var retried = 0;
      await openDialog(tester, queue, onRetry: () => retried++);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Réessayer'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(retried, 1);
      expect((await tester.runAsync(queue.listPending))!.single.id, 'refusee');
      expect(await tester.runAsync(queue.listFailed), isEmpty);
      expect(find.text('Aucune opération à corriger.'), findsOneWidget);
    });

    testWidgets('Supprimer demande confirmation, puis retire définitivement l\'opération', (tester) async {
      final queue = await tester.runAsync(queueWithOneFailure) as SyncQueueService;
      await openDialog(tester, queue);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Supprimer'));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer cette opération ?'), findsOneWidget);

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(queue.listFailed), hasLength(1), reason: 'annulé : rien de supprimé');

      await tester.tap(find.byTooltip('Supprimer'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Supprimer'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(await tester.runAsync(queue.listFailed), isEmpty);
      expect(find.text('Aucune opération à corriger.'), findsOneWidget);
    });
  });
}

String _encode(PendingOperation o) {
  return '{"id":"${o.id}","entityType":"${o.entityType}","deviceId":"${o.deviceId}",'
      '"payload":{"payments":[{"method":"cash","amount":1000}]},'
      '"createdAt":"${o.createdAt.toIso8601String()}","attemptCount":1,"lastError":"${o.lastError}"}';
}
