import 'package:flutter/material.dart';

import 'expenses_form_tab.dart';
import 'expenses_history_tab.dart';
import 'expenses_overview_tab.dart';
import '../payroll/payroll_tab.dart';

/// Module Dépenses restructuré en 4 sous-onglets (demande utilisateur du
/// 2026-09-12, voir docs/api/expenses.md) : Vue d'ensemble, Dépenses,
/// Salaires, Historique. `ExpensesFormTab` est une extraction verbatim de
/// l'ancien écran (aucun changement de comportement).
///
/// `DefaultTabController` plutôt qu'un `TabController` géré à la main : le
/// lien "Voir tout →" de l'onglet Vue d'ensemble (Task 12) navigue vers
/// Historique via `DefaultTabController.of(context).animateTo(3)`, qui exige
/// un `DefaultTabController` ancêtre — `TabBar`/`TabBarView` s'y raccrochent
/// automatiquement dès lors qu'aucun `controller:` explicite n'est fourni.
class ExpensesPage extends StatelessWidget {
  const ExpensesPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dépenses'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: "Vue d'ensemble"),
              Tab(text: 'Dépenses'),
              Tab(text: 'Salaires'),
              Tab(text: 'Historique'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ExpensesOverviewTab(establishmentId: establishmentId),
            ExpensesFormTab(establishmentId: establishmentId),
            PayrollTab(establishmentId: establishmentId),
            ExpensesHistoryTab(establishmentId: establishmentId),
          ],
        ),
      ),
    );
  }
}
