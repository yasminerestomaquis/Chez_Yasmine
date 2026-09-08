import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../expenses/expense_models.dart';
import 'chart_models.dart';
import 'charts_repository.dart';
import 'monthly_line_chart.dart';
import 'ranking_bar_chart.dart';
import 'weekly_bar_chart.dart';

const _monthNames = [
  'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
  'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
];

/// Une couleur par graphique, dominante rouge/bordeaux pour signaler une
/// sortie d'argent — délibérément distincte des palettes bleu (Recettes),
/// violet (Bénéfices) et vert (Stock).
class _ExpensePalette {
  static const dailyTotal = Color(0xFFB71C1C);
  static const dailyByCategory = Color(0xFFD84315);
  static const top = Color(0xFF6D4C41);
  static const monthly = Color(0xFFAD1457);
}

/// Sous-module "Dépenses" du module Graphiques : 4 graphiques (pas 5, comme
/// Recettes/Bénéfices) puisqu'une dépense n'a ni produit ni catégorie de
/// produit, seulement sa propre nature (Loyer, Eau, ... voir
/// `kPredefinedExpenseCategories`) — donc pas de graphique "par produit"
/// ici. Piloté par le même filtre Année que Recettes/Bénéfices (voir
/// `GraphiquesPage`), contrairement à Stock.
class ExpenseChartsTab extends StatefulWidget {
  const ExpenseChartsTab({super.key, required this.establishmentId, required this.year});

  final String establishmentId;
  final int year;

  @override
  State<ExpenseChartsTab> createState() => _ExpenseChartsTabState();
}

class _ExpenseChartsTabState extends State<ExpenseChartsTab> {
  late final ChartsRepository _charts = ChartsRepository(ApiClient(), widget.establishmentId);
  static final DateFormat _dayFormat = DateFormat('dd/MM/yyyy');

  late DateTime _weekAnchor = _clampToYear(DateTime.now(), widget.year);
  String? _category;
  int? _topMonth;

  // `..ignore()` sur chacun de ces futurs initiaux — même garde que
  // MetricChartsTab contre un rejet "unhandled" en test (flutter_test répond
  // quasi instantanément à tout appel réseau).
  late Future<WeeklyChart> _totalFuture = _charts.getExpensesWeekly(weekStart: _weekStartParam)..ignore();
  late Future<WeeklyChart> _byCategoryFuture =
      (_charts.getExpensesWeeklyByCategory(weekStart: _weekStartParam)..ignore());
  late Future<RankingChart> _topFuture = _charts.getExpensesTop(from: _topFrom, to: _topTo)..ignore();
  late final Future<MonthlyChart> _monthlyFuture = _charts.getExpensesMonthly(year: widget.year)..ignore();

  // `GraphiquesPage` recrée ce widget avec une nouvelle clé à chaque
  // changement d'année, donc pas besoin de `didUpdateWidget` — voir
  // metric_charts_tab.dart pour le même motif.
  static DateTime _clampToYear(DateTime date, int year) {
    if (date.year == year) return date;
    final now = DateTime.now();
    return now.year == year ? now : DateTime(year, 1, 15);
  }

  String get _weekStartParam => _weekAnchor.toIso8601String().split('T').first;

  String get _topFrom => (_topMonth == null ? DateTime(widget.year, 1, 1) : DateTime(widget.year, _topMonth! + 1, 1))
      .toIso8601String();

  String get _topTo => (_topMonth == null
          ? DateTime(widget.year, 12, 31, 23, 59, 59)
          : DateTime(widget.year, _topMonth! + 2, 0, 23, 59, 59))
      .toIso8601String();

  void _reloadTotal() {
    final future = _charts.getExpensesWeekly(weekStart: _weekStartParam);
    future.ignore();
    setState(() => _totalFuture = future);
  }

  void _reloadByCategory() {
    final future = _charts.getExpensesWeeklyByCategory(weekStart: _weekStartParam, category: _category);
    future.ignore();
    setState(() => _byCategoryFuture = future);
  }

  void _reloadTop() {
    final future = _charts.getExpensesTop(from: _topFrom, to: _topTo);
    future.ignore();
    setState(() => _topFuture = future);
  }

  Future<void> _pickWeek() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _weekAnchor,
      firstDate: DateTime(widget.year, 1, 1),
      lastDate: DateTime(widget.year, 12, 31),
      helpText: 'Choisir un jour de la semaine à afficher',
    );
    if (picked == null) return;
    setState(() => _weekAnchor = picked);
    _reloadTotal();
    _reloadByCategory();
  }

  Widget _card({required String title, required Widget child, List<Widget>? controls}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (controls != null) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 12, runSpacing: 8, children: controls),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _pickWeekButton() {
    return OutlinedButton.icon(
      onPressed: _pickWeek,
      icon: const Icon(Icons.date_range_outlined, size: 18),
      label: const Text('Choisir la semaine'),
    );
  }

  Widget _futureChart<T>(Future<T> future, Widget Function(T data) builder) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text(message)),
          );
        }
        return builder(snapshot.data as T);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          title: 'Dépenses journalières totales',
          controls: [_pickWeekButton()],
          child: _futureChart(_totalFuture, (chart) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (chart.weekStart.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Semaine du ${_dayFormat.format(DateTime.parse(chart.weekStart))} au ${_dayFormat.format(DateTime.parse(chart.weekEnd))}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                WeeklyBarChartWidget(series: chart.series, baseColor: _ExpensePalette.dailyTotal),
              ],
            );
          }),
        ),
        _card(
          title: 'Dépenses journalières totales par catégorie',
          controls: [
            DropdownButton<String?>(
              value: _category,
              hint: const Text('Toutes les catégories'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Toutes les catégories')),
                for (final category in kPredefinedExpenseCategories)
                  DropdownMenuItem(value: category, child: Text(category)),
              ],
              onChanged: (value) {
                setState(() => _category = value);
                _reloadByCategory();
              },
            ),
          ],
          child: _futureChart(
            _byCategoryFuture,
            (chart) => WeeklyBarChartWidget(series: chart.series, baseColor: _ExpensePalette.dailyByCategory),
          ),
        ),
        _card(
          title: 'Top dépenses',
          controls: [
            DropdownButton<int?>(
              value: _topMonth,
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text("Toute l'année")),
                for (var i = 0; i < _monthNames.length; i++) DropdownMenuItem(value: i, child: Text(_monthNames[i])),
              ],
              onChanged: (value) {
                setState(() => _topMonth = value);
                _reloadTop();
              },
            ),
          ],
          child: _futureChart(
            _topFuture,
            (chart) => RankingBarChartWidget(items: chart.items, color: _ExpensePalette.top),
          ),
        ),
        _card(
          title: 'Dépenses mensuelles',
          child: _futureChart(
            _monthlyFuture,
            (chart) => MonthlyLineChartWidget(months: chart.months, color: _ExpensePalette.monthly),
          ),
        ),
      ],
    );
  }
}
