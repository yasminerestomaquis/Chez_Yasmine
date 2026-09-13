import 'package:flutter/material.dart';

/// Recharge un onglet de `TabBarView` chaque fois que l'utilisateur y
/// navigue depuis un autre onglet.
///
/// `TabBarView` garde tous ses onglets vivants en mémoire en changeant
/// d'onglet — sans ce mixin, une mutation faite dans un autre onglet (ex.
/// payer une paie dans Salaires, ajouter une dépense dans Dépenses) reste
/// invisible ailleurs (Vue d'ensemble, Historique...) tant que l'utilisateur
/// ne quitte pas et ne rouvre pas toute la page (demande utilisateur du
/// 2026-09-13).
mixin ReloadOnTabVisitMixin<T extends StatefulWidget> on State<T> {
  /// Index de cet onglet dans le `TabBarView` parent — doit correspondre à
  /// l'ordre déclaré dans `ExpensesPage`.
  int get tabIndex;

  /// Appelé chaque fois que cet onglet redevient actif après avoir été sur
  /// un autre — typiquement `_reload()`.
  void onTabVisited();

  TabController? _tabController;
  int? _lastIndex;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `maybeOf` (pas `of`) : ce mixin doit rester silencieux — jamais lever
    // d'exception — quand l'onglet est monté hors d'un `DefaultTabController`
    // (tests de widget isolés, réutilisation future ailleurs).
    final controller = DefaultTabController.maybeOf(context);
    if (controller == null) return;
    if (!identical(_tabController, controller)) {
      _tabController?.removeListener(_handleTabChange);
      _tabController = controller;
      _lastIndex = controller.index;
      controller.addListener(_handleTabChange);
    }
  }

  void _handleTabChange() {
    final controller = _tabController;
    if (controller == null) return;
    if (controller.index == tabIndex && _lastIndex != tabIndex) {
      onTabVisited();
    }
    _lastIndex = controller.index;
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabChange);
    super.dispose();
  }
}
