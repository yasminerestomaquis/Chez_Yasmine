import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/users/permission_grouping.dart';
import 'package:chez_yasmine/users/user_models.dart';

void main() {
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
}
