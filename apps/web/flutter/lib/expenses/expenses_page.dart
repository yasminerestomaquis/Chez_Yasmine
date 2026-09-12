import 'package:flutter/material.dart';

import 'expenses_form_tab.dart';
import 'expenses_history_tab.dart';
import 'expenses_overview_tab.dart';
import '../payroll/payroll_tab.dart';

/// Module Dépenses restructuré en 4 sous-onglets (demande utilisateur du
/// 2026-09-12, voir docs/api/expenses.md) : Vue d'ensemble, Dépenses,
/// Salaires, Historique. `ExpensesFormTab` est une extraction verbatim de
/// l'ancien écran (aucun changement de comportement).
class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 4,
    vsync: this,
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dépenses'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: "Vue d'ensemble"),
            Tab(text: 'Dépenses'),
            Tab(text: 'Salaires'),
            Tab(text: 'Historique'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ExpensesOverviewTab(establishmentId: widget.establishmentId),
          ExpensesFormTab(establishmentId: widget.establishmentId),
          PayrollTab(establishmentId: widget.establishmentId),
          ExpensesHistoryTab(establishmentId: widget.establishmentId),
        ],
      ),
    );
  }
}
