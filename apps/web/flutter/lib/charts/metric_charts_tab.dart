import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import 'chart_models.dart';
import 'charts_repository.dart';
import 'monthly_line_chart.dart';
import 'ranking_bar_chart.dart';
import 'weekly_bar_chart.dart';

/// Une couleur différente par graphique au sein d'un même sous-module,
/// comme demandé ("Mets une différence de couleur par type de graphique").
class ChartPalette {
  const ChartPalette({
    required this.dailyTotal,
    required this.dailyByCategory,
    required this.dailyByProduct,
    required this.top,
    required this.monthly,
  });

  final Color dailyTotal;
  final Color dailyByCategory;
  final Color dailyByProduct;
  final Color top;
  final Color monthly;
}

/// Les intitulés exacts diffèrent entre Recettes ("journalières totales",
/// féminin) et Bénéfices ("journaliers totaux", masculin) — on les passe tels
/// quels plutôt que de tenter un accord automatique.
class ChartTitles {
  const ChartTitles({
    required this.dailyTotal,
    required this.dailyByCategory,
    required this.dailyByProduct,
    required this.top,
    required this.monthly,
  });

  final String dailyTotal;
  final String dailyByCategory;
  final String dailyByProduct;
  final String top;
  final String monthly;
}

const _monthNames = [
  'Janvier',
  'Février',
  'Mars',
  'Avril',
  'Mai',
  'Juin',
  'Juillet',
  'Août',
  'Septembre',
  'Octobre',
  'Novembre',
  'Décembre',
];

/// Les 5 graphiques d'un sous-module (Recettes ou Bénéfices), identiques dans
/// leur structure — seuls [metric] (envoyé à l'API), [titles] et [palette]
/// changent entre les deux. L'année ([year]) est pilotée par la page parente
/// (`GraphiquesPage`) et agit sur les 5 graphiques.
class MetricChartsTab extends StatefulWidget {
  const MetricChartsTab({
    super.key,
    required this.establishmentId,
    required this.year,
    required this.metric,
    required this.titles,
    required this.palette,
  });

  final String establishmentId;
  final int year;
  final String metric;
  final ChartTitles titles;
  final ChartPalette palette;

  @override
  State<MetricChartsTab> createState() => _MetricChartsTabState();
}

class _MetricChartsTabState extends State<MetricChartsTab> {
  late final ChartsRepository _charts = ChartsRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final CatalogRepository _catalog = CatalogRepository(
    ApiClient(),
    widget.establishmentId,
  );
  static final DateFormat _dayFormat = DateFormat('dd/MM/yyyy');

  late DateTime _weekAnchor = _clampToYear(DateTime.now(), widget.year);
  final Set<String> _selectedCategoryIds = {};
  String? _productId;
  int? _topMonth;

  List<Category> _categories = [];
  List<Product> _products = [];

  // `..ignore()` sur chacun de ces futurs initiaux, pour la même raison que
  // `future.ignore()` dans reports_page.dart : `flutter_test` répond à tout
  // appel réseau par un faux échec quasi instantané, assez tôt pour parfois
  // rejeter avant que `FutureBuilder` ne s'y abonne, ce que Dart signalerait
  // sinon comme une erreur non gérée alors que l'UI l'affiche normalement.
  late Future<WeeklyChart> _totalFuture = _charts.getWeekly(
    metric: widget.metric,
    weekStart: _weekStartParam,
  )..ignore();
  late Future<WeeklyChart> _byCategoryFuture = (_charts.getWeeklyByCategory(
    metric: widget.metric,
    weekStart: _weekStartParam,
    categoryIds: _selectedCategoryIds,
  )..ignore());
  late Future<WeeklyChart> _byProductFuture = (_charts.getWeeklyByProduct(
    metric: widget.metric,
    weekStart: _weekStartParam,
  )..ignore());
  late Future<RankingChart> _topFuture = _charts.getTop(
    metric: widget.metric,
    from: _topFrom,
    to: _topTo,
  )..ignore();
  late final Future<MonthlyChart> _monthlyFuture = _charts.getMonthly(
    metric: widget.metric,
    year: widget.year,
  )..ignore();

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  // `GraphiquesPage` recrée ce widget avec une nouvelle clé à chaque
  // changement d'année (voir `ValueKey('$prefix-$year')`), donc un nouveau
  // `State` est construit avec `widget.year` déjà à jour — pas besoin de
  // `didUpdateWidget` pour réagir à ce changement.
  static DateTime _clampToYear(DateTime date, int year) {
    if (date.year == year) return date;
    final now = DateTime.now();
    return now.year == year ? now : DateTime(year, 1, 15);
  }

  String get _weekStartParam => _weekAnchor.toIso8601String().split('T').first;

  String get _topFrom =>
      (_topMonth == null
              ? DateTime(widget.year, 1, 1)
              : DateTime(widget.year, _topMonth! + 1, 1))
          .toIso8601String();

  String get _topTo =>
      (_topMonth == null
              ? DateTime(widget.year, 12, 31, 23, 59, 59)
              : DateTime(widget.year, _topMonth! + 2, 0, 23, 59, 59))
          .toIso8601String();

  Future<void> _loadFilters() async {
    try {
      final categories = await _catalog.listCategories();
      final products = await _catalog.listProducts();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _products = products;
        _productId = products.isNotEmpty ? products.first.id : null;
      });
      _reloadByProduct();
    } catch (_) {
      // Les filtres restent vides ; chaque graphique affiche déjà son propre
      // état d'erreur via son FutureBuilder si l'appel réseau échoue.
    }
  }

  void _reloadTotal() {
    final future = _charts.getWeekly(
      metric: widget.metric,
      weekStart: _weekStartParam,
    );
    future.ignore();
    setState(() => _totalFuture = future);
  }

  void _reloadByCategory() {
    final future = _charts.getWeeklyByCategory(
      metric: widget.metric,
      weekStart: _weekStartParam,
      categoryIds: _selectedCategoryIds,
    );
    future.ignore();
    setState(() => _byCategoryFuture = future);
  }

  void _toggleCategory(String categoryId) {
    setState(() {
      if (_selectedCategoryIds.contains(categoryId)) {
        _selectedCategoryIds.remove(categoryId);
      } else {
        _selectedCategoryIds.add(categoryId);
      }
    });
    _reloadByCategory();
  }

  void _reloadByProduct() {
    final future = _charts.getWeeklyByProduct(
      metric: widget.metric,
      weekStart: _weekStartParam,
      productId: _productId,
    );
    future.ignore();
    setState(() => _byProductFuture = future);
  }

  void _reloadTop() {
    final future = _charts.getTop(
      metric: widget.metric,
      from: _topFrom,
      to: _topTo,
    );
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
    _reloadByProduct();
  }

  Widget _card({
    required String title,
    required Widget child,
    List<Widget>? controls,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
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
          final message = snapshot.error is ApiException
              ? (snapshot.error as ApiException).message
              : '${snapshot.error}';
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
          title: widget.titles.dailyTotal,
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
                WeeklyBarChartWidget(
                  series: chart.series,
                  baseColor: widget.palette.dailyTotal,
                ),
              ],
            );
          }),
        ),
        _card(
          title: widget.titles.dailyByCategory,
          controls: [
            if (_categories.isEmpty)
              const Text('Aucune catégorie au catalogue')
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilterChip(
                    label: const Text('Toutes'),
                    selected: _selectedCategoryIds.isEmpty,
                    onSelected: (_) {
                      setState(() => _selectedCategoryIds.clear());
                      _reloadByCategory();
                    },
                  ),
                  for (final category in _categories)
                    FilterChip(
                      label: Text(category.name),
                      selected: _selectedCategoryIds.contains(category.id),
                      onSelected: (_) => _toggleCategory(category.id),
                    ),
                ],
              ),
          ],
          child: _futureChart(
            _byCategoryFuture,
            (chart) => WeeklyBarChartWidget(
              series: chart.series,
              baseColor: widget.palette.dailyByCategory,
            ),
          ),
        ),
        _card(
          title: widget.titles.dailyByProduct,
          controls: [
            if (_products.isNotEmpty)
              DropdownButton<String?>(
                value: _productId,
                items: [
                  for (final product in _products)
                    DropdownMenuItem(
                      value: product.id,
                      child: Text(product.name),
                    ),
                ],
                onChanged: (value) {
                  setState(() => _productId = value);
                  _reloadByProduct();
                },
              )
            else
              const Text('Aucun produit au catalogue'),
          ],
          child: _futureChart(
            _byProductFuture,
            (chart) => WeeklyBarChartWidget(
              series: chart.series,
              baseColor: widget.palette.dailyByProduct,
            ),
          ),
        ),
        _card(
          title: widget.titles.top,
          controls: [
            DropdownButton<int?>(
              value: _topMonth,
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text("Toute l'année"),
                ),
                for (var i = 0; i < _monthNames.length; i++)
                  DropdownMenuItem(value: i, child: Text(_monthNames[i])),
              ],
              onChanged: (value) {
                setState(() => _topMonth = value);
                _reloadTop();
              },
            ),
          ],
          child: _futureChart(
            _topFuture,
            (chart) => RankingBarChartWidget(
              items: chart.items,
              color: widget.palette.top,
            ),
          ),
        ),
        _card(
          title: widget.titles.monthly,
          child: _futureChart(
            _monthlyFuture,
            (chart) => MonthlyLineChartWidget(
              months: chart.months,
              color: widget.palette.monthly,
            ),
          ),
        ),
      ],
    );
  }
}
