import 'user_models.dart';

/// Regroupement Module > Sous-module d'une [PermissionInfo] pour le tableau
/// de bord "Gestion des permissions" — dérivé du préfixe de `permission.code`
/// (ex. `products.manage` -> Catalogue), jamais d'une colonne dédiée en base
/// (voir docs/api/users.md, "Regroupement par module"). Garde ce fichier
/// libre de tout import Flutter pour rester testable sans harnais de widget.
class PermissionSubModuleGroup {
  const PermissionSubModuleGroup({
    required this.name,
    required this.permissions,
  });

  final String name;
  final List<PermissionInfo> permissions;
}

class PermissionModuleGroup {
  const PermissionModuleGroup({required this.name, required this.subModules});

  final String name;
  final List<PermissionSubModuleGroup> subModules;
}

/// Préfixe de code -> module affiché. Plusieurs préfixes peuvent partager un
/// même module (ex. `payroll`/`expenses` -> Dépenses, puisque la paie est un
/// sous-onglet du module Dépenses côté Flutter ; `users`/`roles` ->
/// Utilisateurs, ce tableau de bord étant lui-même une fonctionnalité de ce
/// module).
const Map<String, String> _prefixToModule = {
  'tables': 'Tables',
  'pos': 'Caisse',
  'stock': 'Stock',
  'purchases': 'Achats',
  'expenses': 'Dépenses',
  'payroll': 'Dépenses',
  'losses': 'Pertes',
  'customers': 'Clients',
  'credits': 'Clients',
  'products': 'Catalogue',
  'reports': 'Rapports',
  'charts.revenue': 'Graphiques',
  'charts.profit': 'Graphiques',
  'charts.stock': 'Graphiques',
  'charts.expenses': 'Graphiques',
  'cash': 'Clôture de caisse',
  'notifications': 'Notifications',
  'settings': 'Paramètres',
  'users': 'Utilisateurs',
  'roles': 'Utilisateurs',
};

const Map<String, String> _prefixToSubModule = {
  'tables': 'Plan de salle',
  'pos': 'Vente',
  'stock': 'Mouvements de stock',
  'purchases': 'Commandes fournisseurs',
  'expenses': 'Dépenses courantes',
  'payroll': 'Salaires & paie',
  'losses': 'Pertes',
  'customers': 'Fiches client',
  'credits': 'Crédits',
  'products': 'Catalogue',
  'reports': 'Rapports',
  'charts.revenue': 'Recettes',
  'charts.profit': 'Bénéfices',
  'charts.stock': 'Stock',
  'charts.expenses': 'Dépenses',
  'cash': 'Ouverture / clôture',
  'notifications': 'Notifications',
  'settings': 'Paramètres',
  'users': 'Membres',
  'roles': 'Permissions',
};

/// Ordre d'affichage des préfixes, pour un tableau de bord stable et
/// prévisible plutôt que l'ordre alphabétique des codes renvoyé par l'API.
const List<String> _prefixOrder = [
  'tables',
  'pos',
  'stock',
  'purchases',
  'expenses',
  'payroll',
  'losses',
  'customers',
  'credits',
  'products',
  'reports',
  'charts.revenue',
  'charts.profit',
  'charts.stock',
  'charts.expenses',
  'cash',
  'notifications',
  'settings',
  'users',
  'roles',
];

/// Clé de regroupement d'un code : son préfixe (`products.manage` ->
/// `products`), sauf pour les graphiques (`charts.revenue_daily` ->
/// `charts.revenue`) où le sous-module (Recettes, Bénéfices, Stock, Dépenses)
/// est le segment avant le premier `_` — une permission par graphique,
/// décision utilisateur du 2026-09-20.
String modulePrefixOf(String code) {
  final prefix = code.split('.').first;
  if (prefix != 'charts') return prefix;
  final rest = code.length > 7 ? code.substring(7) : '';
  return 'charts.${rest.split('_').first}';
}

/// Module affiché pour un code de permission — un préfixe inconnu (une
/// permission ajoutée sans mettre à jour cette table) retombe sur son
/// préfixe capitalisé plutôt que de disparaître silencieusement du tableau
/// de bord.
String moduleNameFor(String code) {
  final prefix = modulePrefixOf(code);
  return _prefixToModule[prefix] ?? _capitalize(prefix);
}

String subModuleNameFor(String code) {
  final prefix = modulePrefixOf(code);
  return _prefixToSubModule[prefix] ?? _capitalize(prefix);
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Ordre naturel des graphiques d'un sous-module (journalier, par catégorie,
/// par produit, top, mensuel ; Stock : détail puis épuisés) plutôt que
/// l'ordre alphabétique des codes renvoyé par l'API.
const List<String> _chartKindOrder = [
  'daily',
  'by_category',
  'by_product',
  'top',
  'monthly',
  'lots',
  'out',
];

List<PermissionInfo> _sortedChartPermissions(List<PermissionInfo> items) {
  int rank(PermissionInfo p) {
    final kind = p.code.substring(p.code.indexOf('_') + 1);
    final index = _chartKindOrder.indexOf(kind);
    return index == -1 ? _chartKindOrder.length : index;
  }

  return [...items]..sort((a, b) => rank(a).compareTo(rank(b)));
}

/// Groupe une liste de permissions en modules puis sous-modules, dans
/// l'ordre stable de [_prefixOrder] (les préfixes inconnus sont ajoutés à la
/// fin, dans leur ordre d'apparition). L'ordre des permissions au sein d'un
/// même sous-module suit l'ordre d'entrée de [permissions].
List<PermissionModuleGroup> groupPermissionsByModule(
  List<PermissionInfo> permissions,
) {
  final byPrefix = <String, List<PermissionInfo>>{};
  for (final permission in permissions) {
    byPrefix
        .putIfAbsent(modulePrefixOf(permission.code), () => [])
        .add(permission);
  }

  final orderedPrefixes = [
    ..._prefixOrder.where(byPrefix.containsKey),
    ...byPrefix.keys.where((p) => !_prefixOrder.contains(p)),
  ];

  final subModulesByModule = <String, List<PermissionSubModuleGroup>>{};
  for (final prefix in orderedPrefixes) {
    final modulePermissions = prefix.startsWith('charts.')
        ? _sortedChartPermissions(byPrefix[prefix]!)
        : byPrefix[prefix]!;
    final moduleName = _prefixToModule[prefix] ?? _capitalize(prefix);
    final subModuleName = _prefixToSubModule[prefix] ?? _capitalize(prefix);
    subModulesByModule
        .putIfAbsent(moduleName, () => [])
        .add(
          PermissionSubModuleGroup(
            name: subModuleName,
            permissions: modulePermissions,
          ),
        );
  }

  return [
    for (final entry in subModulesByModule.entries)
      PermissionModuleGroup(name: entry.key, subModules: entry.value),
  ];
}

/// Une ligne de la matrice affichée par `PermissionsDashboardPage` — soit un
/// en-tête de section (module ou sous-module), soit une permission à cocher.
sealed class MatrixRow {
  const MatrixRow();
}

class ModuleHeaderRow extends MatrixRow {
  const ModuleHeaderRow(this.label);
  final String label;
}

class SubModuleHeaderRow extends MatrixRow {
  const SubModuleHeaderRow(this.label);
  final String label;
}

class PermissionRow extends MatrixRow {
  const PermissionRow(this.permission);
  final PermissionInfo permission;
}

/// Aplatit [groupPermissionsByModule] en une seule liste de lignes, dans
/// l'ordre d'affichage — colonne figée et corps de la matrice partagent
/// exactement cette liste (source unique de vérité) pour rester alignés quel
/// que soit le défilement. Le libellé de sous-module n'est affiché que si un
/// module en compte plusieurs (ex. Dépenses : "Dépenses courantes" +
/// "Salaires & paie") — un module à un seul sous-module n'ajoute rien à
/// l'information déjà donnée par son propre en-tête.
List<MatrixRow> buildMatrixRows(List<PermissionInfo> permissions) {
  final rows = <MatrixRow>[];
  for (final module in groupPermissionsByModule(permissions)) {
    rows.add(ModuleHeaderRow(module.name));
    final showSubModuleLabels = module.subModules.length > 1;
    for (final subModule in module.subModules) {
      if (showSubModuleLabels) rows.add(SubModuleHeaderRow(subModule.name));
      for (final permission in subModule.permissions) {
        rows.add(PermissionRow(permission));
      }
    }
  }
  return rows;
}
