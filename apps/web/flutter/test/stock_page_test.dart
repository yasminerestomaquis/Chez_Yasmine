import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chez_yasmine/catalog/models.dart';
import 'package:chez_yasmine/stock/stock_models.dart';
import 'package:chez_yasmine/stock/stock_page.dart';

Product _product({
  required String id,
  required String name,
  required double stockQuantity,
  String? categoryId,
  Category? category,
  double? minStock,
}) => Product(
  id: id,
  name: name,
  status: 'active',
  stockQuantity: stockQuantity,
  categoryId: categoryId,
  category: category,
  minStock: minStock,
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'https://example.supabase.co', publishableKey: 'test-anon-key');
  });

  final biere = Category(id: 'cat-1', name: 'Bières');
  final plats = Category(id: 'cat-2', name: 'Plats africains');

  group('stockStatusOf (logique pure, sans réseau)', () {
    test('rupture dès que le stock est à zéro ou négatif, même avec une alerte', () {
      final alert = StockAlert(id: 'p1', name: 'x', stockQuantity: 0, minStock: 5);
      expect(stockStatusOf(_product(id: 'p1', name: 'x', stockQuantity: 0), alert), 'out');
      expect(stockStatusOf(_product(id: 'p1', name: 'x', stockQuantity: -1), null), 'out');
    });

    test('stock faible quand une alerte existe et le stock est positif', () {
      final alert = StockAlert(id: 'p1', name: 'x', stockQuantity: 2, minStock: 5);
      expect(stockStatusOf(_product(id: 'p1', name: 'x', stockQuantity: 2), alert), 'low');
    });

    test('normal sans alerte et stock positif', () {
      expect(stockStatusOf(_product(id: 'p1', name: 'x', stockQuantity: 10), null), 'in_stock');
    });
  });

  group('filterAndSortStockProducts (logique pure, sans réseau)', () {
    final products = [
      _product(id: 'p1', name: 'Heineken 33', stockQuantity: 12, categoryId: 'cat-1', category: biere),
      _product(id: 'p2', name: 'Placali Sauce', stockQuantity: 3, categoryId: 'cat-2', category: plats),
      _product(id: 'p3', name: 'Bock 66', stockQuantity: 0, categoryId: 'cat-1', category: biere),
    ];

    test('trie par ordre croissant du stock actuel', () {
      final result = filterAndSortStockProducts(
        products: products,
        alertsByProduct: const {},
        search: '',
        statusFilter: 'all',
        selectedCategoryIds: const {},
      );

      expect(result.map((p) => p.id), ['p3', 'p2', 'p1']); // 0, 3, 12
    });

    test('filtre par recherche (insensible à la casse)', () {
      final result = filterAndSortStockProducts(
        products: products,
        alertsByProduct: const {},
        search: 'heine',
        statusFilter: 'all',
        selectedCategoryIds: const {},
      );

      expect(result.map((p) => p.id), ['p1']);
    });

    test('selectedCategoryIds vide = toutes les catégories (aucun filtre)', () {
      final result = filterAndSortStockProducts(
        products: products,
        alertsByProduct: const {},
        search: '',
        statusFilter: 'all',
        selectedCategoryIds: const {},
      );

      expect(result, hasLength(3));
    });

    test('sélection multiple de catégories : inclut chaque produit appartenant à au moins une des catégories choisies', () {
      final result = filterAndSortStockProducts(
        products: products,
        alertsByProduct: const {},
        search: '',
        statusFilter: 'all',
        selectedCategoryIds: {'cat-1', 'cat-2'},
      );

      expect(result, hasLength(3));

      final onlyBieres = filterAndSortStockProducts(
        products: products,
        alertsByProduct: const {},
        search: '',
        statusFilter: 'all',
        selectedCategoryIds: {'cat-1'},
      );

      expect(onlyBieres.map((p) => p.id), ['p3', 'p1']); // Bock 66 (0), Heineken 33 (12) — Placali Sauce exclu
    });

    test('combine recherche, catégorie et statut ensemble', () {
      final result = filterAndSortStockProducts(
        products: products,
        alertsByProduct: const {},
        search: '',
        statusFilter: 'out',
        selectedCategoryIds: {'cat-1'},
      );

      expect(result.map((p) => p.id), ['p3']); // seul Bock 66 est à la fois "Bières" et en rupture
    });
  });

  testWidgets('shows an error state without crashing when no backend is reachable in test', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: StockPage(establishmentId: 'est-1', roleName: 'Gérant')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stock'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'tapping the "Stock actif" export button surfaces a snackbar instead of crashing when no backend is reachable (2026-09-25)',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: StockPage(establishmentId: 'est-1', roleName: 'Gérant')),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Stock actif (listing, export PDF)'), findsOneWidget);

      await tester.tap(find.byTooltip('Stock actif (listing, export PDF)'));
      // Même raison que le test de changement de période dans
      // reports_page_test.dart : pumpAndSettle (pas un seul pump) exerce la
      // course entre le rejet réseau instantané de flutter_test et la
      // souscription du FutureBuilder/du gestionnaire d'erreur.
      await tester.pumpAndSettle();

      expect(find.text('Stock actif'), findsNothing); // le dialogue ne s'ouvre pas sur erreur réseau
      expect(find.byType(SnackBar), findsOneWidget);
    },
  );
}
