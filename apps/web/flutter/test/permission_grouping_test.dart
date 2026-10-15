import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/users/permission_grouping.dart';
import 'package:chez_yasmine/users/user_models.dart';

void main() {
  accueilGroupingTests();

  group('moduleNameFor / subModuleNameFor', () {
    test('maps known prefixes to their French module/sub-module labels', () {
      expect(moduleNameFor('products.manage'), 'Catalogue');
      expect(subModuleNameFor('products.manage'), 'Catalogue');
      expect(moduleNameFor('pos.refund'), 'Caisse');
      expect(moduleNameFor('users.manage'), 'Utilisateurs');
      expect(moduleNameFor('roles.manage'), 'Utilisateurs');
      expect(subModuleNameFor('roles.manage'), 'Permissions');
    });

    test('groups payroll and expenses under the same "Dépenses" module', () {
      expect(moduleNameFor('payroll.manage'), 'Dépenses');
      expect(moduleNameFor('expenses.manage'), 'Dépenses');
      expect(subModuleNameFor('payroll.manage'), 'Salaires & paie');
    });

    test('groups credits and customers under the same "Clients" module', () {
      expect(moduleNameFor('credits.manage'), 'Clients');
      expect(moduleNameFor('customers.manage'), 'Clients');
    });

    test('falls back to a capitalized prefix for an unmapped code', () {
      expect(moduleNameFor('billing.manage'), 'Billing');
      expect(subModuleNameFor('billing.manage'), 'Billing');
    });
  });

  group('groupPermissionsByModule', () {
    PermissionInfo p(String code) => PermissionInfo(code: code, description: code);

    test('orders modules by the fixed display order, not the input order', () {
      final groups = groupPermissionsByModule([
        p('users.manage'),
        p('products.manage'),
        p('tables.manage'),
      ]);

      expect(groups.map((g) => g.name).toList(), [
        'Tables',
        'Catalogue',
        'Utilisateurs',
      ]);
    });

    test('merges permissions from different prefixes into the same module', () {
      final groups = groupPermissionsByModule([
        p('expenses.manage'),
        p('payroll.manage'),
        p('payroll.view'),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.name, 'Dépenses');
      expect(
        groups.single.subModules.map((s) => s.name).toList(),
        ['Dépenses courantes', 'Salaires & paie'],
      );
      expect(groups.single.subModules[1].permissions.map((p) => p.code), [
        'payroll.manage',
        'payroll.view',
      ]);
    });

    test('keeps permissions of a single-submodule group in input order', () {
      final groups = groupPermissionsByModule([
        p('pos.correct'),
        p('pos.sell'),
        p('pos.refund'),
      ]);

      expect(groups.single.subModules.single.permissions.map((p) => p.code), [
        'pos.correct',
        'pos.sell',
        'pos.refund',
      ]);
    });

    test('appends unmapped prefixes at the end, in first-appearance order', () {
      final groups = groupPermissionsByModule([
        p('billing.manage'),
        p('tables.manage'),
        p('audit.view'),
      ]);

      expect(groups.map((g) => g.name).toList(), [
        'Tables',
        'Billing',
        'Audit',
      ]);
    });
  });

  group('buildMatrixRows', () {
    PermissionInfo p(String code) => PermissionInfo(code: code, description: code);

    test('omits the sub-module label when a module has only one sub-module', () {
      final rows = buildMatrixRows([p('tables.manage')]);

      expect(rows, [
        isA<ModuleHeaderRow>().having((r) => r.label, 'label', 'Tables'),
        isA<PermissionRow>().having(
          (r) => r.permission.code,
          'code',
          'tables.manage',
        ),
      ]);
    });

    test('shows the sub-module label when a module has several sub-modules', () {
      final rows = buildMatrixRows([p('expenses.manage'), p('payroll.manage')]);

      expect(rows, [
        isA<ModuleHeaderRow>().having((r) => r.label, 'label', 'Dépenses'),
        isA<SubModuleHeaderRow>().having(
          (r) => r.label,
          'label',
          'Dépenses courantes',
        ),
        isA<PermissionRow>().having(
          (r) => r.permission.code,
          'code',
          'expenses.manage',
        ),
        isA<SubModuleHeaderRow>().having(
          (r) => r.label,
          'label',
          'Salaires & paie',
        ),
        isA<PermissionRow>().having(
          (r) => r.permission.code,
          'code',
          'payroll.manage',
        ),
      ]);
    });
  });

  group('Graphiques (2026-09-20) — une permission par graphique', () {
    PermissionInfo p(String code) => PermissionInfo(code: code, description: code);

    test('les codes charts.* se regroupent en module Graphiques avec 4 sous-modules', () {
      expect(moduleNameFor('charts.revenue_daily'), 'Graphiques');
      expect(subModuleNameFor('charts.revenue_daily'), 'Recettes');
      expect(subModuleNameFor('charts.profit_top'), 'Bénéfices');
      expect(subModuleNameFor('charts.stock_lots'), 'Stock');
      expect(subModuleNameFor('charts.expenses_monthly'), 'Dépenses');
    });

    test('un seul module Graphiques, sous-modules dans l ordre Recettes, Bénéfices, Stock, Dépenses', () {
      final groups = groupPermissionsByModule([
        p('charts.expenses_top'),
        p('charts.stock_out'),
        p('charts.profit_daily'),
        p('charts.revenue_daily'),
      ]);

      expect(groups, hasLength(1));
      expect(groups.single.name, 'Graphiques');
      expect(groups.single.subModules.map((s) => s.name).toList(), [
        'Recettes',
        'Bénéfices',
        'Stock',
        'Dépenses',
      ]);
    });

    test('les graphiques d un sous-module suivent l ordre naturel, pas l ordre alphabétique', () {
      final groups = groupPermissionsByModule([
        p('charts.revenue_by_category'),
        p('charts.revenue_by_product'),
        p('charts.revenue_daily'),
        p('charts.revenue_monthly'),
        p('charts.revenue_top'),
      ]);

      expect(groups.single.subModules.single.permissions.map((x) => x.code).toList(), [
        'charts.revenue_daily',
        'charts.revenue_by_category',
        'charts.revenue_by_product',
        'charts.revenue_top',
        'charts.revenue_monthly',
      ]);
    });
  });
}

/// Demande du 2026-10-15 : module « Accueil » dans la gestion des permissions,
/// une permission d'affichage par carte, en trois sections.
void accueilGroupingTests() {
  PermissionInfo p(String code) => PermissionInfo(code: code, description: code);

  group('module Accueil (2026-10-15)', () {
    final codes = [
      'home.detail_plats_mobile',
      'home.cash',
      'home.revenue_plats',
      'home.total_sales',
      'home.detail_beverages_cash',
      'home.stock_alerts',
      'home.revenue_beverages',
      'home.mobile_money',
      'home.orders',
    ];

    test('les codes home.* forment le module Accueil, trois sections, en tête du tableau', () {
      final groups = groupPermissionsByModule([p('tables.manage'), for (final c in codes) p(c)]);

      expect(groups.first.name, 'Accueil');
      expect(groups.first.subModules.map((s) => s.name).toList(), [
        'Résumé',
        'Recettes du jour',
        'Détail par mode de paiement',
      ]);
      expect(groups.map((g) => g.name).toList(), ['Accueil', 'Tables']);
    });

    test('les cartes suivent l ordre de l écran, pas l ordre alphabétique', () {
      final groups = groupPermissionsByModule([for (final c in codes) p(c)]);
      final byName = {for (final s in groups.single.subModules) s.name: s.permissions.map((x) => x.code).toList()};

      expect(byName['Résumé'], ['home.total_sales', 'home.cash', 'home.mobile_money', 'home.orders', 'home.stock_alerts']);
      expect(byName['Recettes du jour'], ['home.revenue_beverages', 'home.revenue_plats']);
      expect(byName['Détail par mode de paiement'], ['home.detail_beverages_cash', 'home.detail_plats_mobile']);
    });

    test('les permissions de saisie des recettes (pos.sell_*) restent dans le module Caisse', () {
      expect(moduleNameFor('pos.sell_beverages'), 'Caisse');
      expect(moduleNameFor('pos.sell_gbele'), 'Caisse');
      expect(moduleNameFor('pos.sell_plats'), 'Caisse');
    });
  });
}
