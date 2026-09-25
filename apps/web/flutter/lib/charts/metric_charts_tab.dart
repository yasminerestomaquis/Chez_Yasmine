import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../theme/app_theme.dart';
import 'chart_models.dart';
import 'charts_repository.dart';
import 'monthly_line_chart.dart';
import 'ranking_bar_chart.dart';
import 'week_selection.dart';
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
    required this.permissionKey,
    required this.allowed,
    required this.titles,
    required this.palette,
    this.groupNetVsGross = false,
  });

  final String establishmentId;
  final int year;
  final String metric;

  /// `revenue` ou `profit` — préfixe des permissions `charts.<clé>_<graphique>`.
  final String permissionKey;

  /// Codes `charts.*` accordés (voir `GraphiquesPage`) : un graphique non
  /// autorisé n'est ni affiché ni interrogé.
  final Set<String> allowed;
  final ChartTitles titles;
  final ChartPalette palette;

  /// Vrai uniquement pour Bénéfices (décision utilisateur du 2026-09-25) :
  /// sépare visuellement les graphiques qui déduisent TOUTES les dépenses et
  /// pertes (Total, Mensuel — un vrai « bénéfice net ») de ceux qui n'en
  /// déduisent aucune (Par catégorie, Par produit, Top — une simple « marge
  /// brute », voir le commentaire sur `soldLines` dans `ChartsService` pour
  /// pourquoi une dépense générale ne peut pas être répartie par
  /// catégorie/produit). Sans cette séparation, les deux notions se
  /// mélangeaient sous le même mot « Bénéfices » sur un seul onglet — au
  /// point qu'une même semaine pouvait afficher un Total négatif à côté d'une
  /// ventilation par catégorie positive, sans rien pour expliquer l'écart.
  /// Recettes n'a pas cette dualité (`valueOf('revenue', ...)` ne soustrait
  /// jamais rien) et garde donc l'ordre à plat historique.
  final bool groupNetVsGross;

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

  // Sélection multiple de semaines, réinitialisable (demande utilisateur du
  // 2026-09-24) — chaque semaine ramenée à son lundi (`mondayOfWeek`) pour
  // dédoublonner deux dates de la même semaine ISO. `mergeWeeklyCharts`
  // (week_selection.dart) additionne les graphiques de chaque semaine
  // côté client, le serveur ne résolvant qu'une semaine à la fois.
  late Set<DateTime> _weekAnchors = {mondayOfWeek(_clampToYear(DateTime.now(), widget.year))};
  final Set<String> _selectedCategoryIds = {};
  // Sélection multiple, réinitialisable (demande utilisateur du 2026-09-22) —
  // vide = tous les produits (agrégés en une seule série, comme sans filtre).
  Set<String> _selectedProductIds = {};
  int? _topMonth;

  List<Category> _categories = [];
  List<Product> _products = [];

  // `..ignore()` sur chacun de ces futurs initiaux, pour la même raison que
  // `future.ignore()` dans reports_page.dart : `flutter_test` répond à tout
  // appel réseau par un faux échec quasi instantané, assez tôt pour parfois
  // rejeter avant que `FutureBuilder` ne s'y abonne, ce que Dart signalerait
  // sinon comme une erreur non gérée alors que l'UI l'affiche normalement.
  late Future<WeeklyChart> _totalFuture = _multiWeek(
    (ws) => _charts.getWeekly(metric: widget.metric, weekStart: ws),
  )..ignore();
  late Future<WeeklyChart> _byCategoryFuture = _multiWeek(
    (ws) => _charts.getWeeklyByCategory(metric: widget.metric, weekStart: ws, categoryIds: _selectedCategoryIds),
  )..ignore();
  late Future<WeeklyChart> _byProductFuture = _multiWeek(
    (ws) => _charts.getWeeklyByProduct(metric: widget.metric, weekStart: ws, productIds: _selectedProductIds),
  )..ignore();
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

  bool _can(String kind) => widget.allowed.contains('charts.${widget.permissionKey}_$kind');

  /// Récupère un graphique hebdomadaire pour chaque semaine sélectionnée et
  /// les fusionne (`mergeWeeklyCharts`) — le serveur ne résout qu'une
  /// semaine à la fois par requête.
  Future<WeeklyChart> _multiWeek(Future<WeeklyChart> Function(String weekStart) fetchOne) {
    return Future.wait(
      _weekAnchors.map((a) => fetchOne(a.toIso8601String().split('T').first)),
    ).then(mergeWeeklyCharts);
  }

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
      });
      _reloadByProduct();
    } catch (_) {
      // Les filtres restent vides ; chaque graphique affiche déjà son propre
      // état d'erreur via son FutureBuilder si l'appel réseau échoue.
    }
  }

  void _reloadTotal() {
    if (!_can('daily')) return;
    final future = _multiWeek((ws) => _charts.getWeekly(metric: widget.metric, weekStart: ws));
    future.ignore();
    setState(() => _totalFuture = future);
  }

  void _reloadByCategory() {
    if (!_can('by_category')) return;
    final future = _multiWeek(
      (ws) => _charts.getWeeklyByCategory(metric: widget.metric, weekStart: ws, categoryIds: _selectedCategoryIds),
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
    if (!_can('by_product')) return;
    final future = _multiWeek(
      (ws) => _charts.getWeeklyByProduct(metric: widget.metric, weekStart: ws, productIds: _selectedProductIds),
    );
    future.ignore();
    setState(() => _byProductFuture = future);
  }

  void _toggleProductSelection(Set<String> ids) {
    setState(() => _selectedProductIds = ids);
    _reloadByProduct();
  }

  void _reloadTop() {
    if (!_can('top')) return;
    final future = _charts.getTop(
      metric: widget.metric,
      from: _topFrom,
      to: _topTo,
    );
    future.ignore();
    setState(() => _topFuture = future);
  }

  Future<void> _pickWeeks() async {
    final result = await pickWeeks(context, selected: _weekAnchors, year: widget.year);
    if (result == null) return;
    setState(() => _weekAnchors = result);
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
      onPressed: _pickWeeks,
      icon: const Icon(Icons.date_range_outlined, size: 18),
      label: Text(weekFilterLabel(_weekAnchors)),
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

  /// En-tête de section (« BÉNÉFICE NET » / « MARGE BRUTE »), même style que
  /// les titres de section d'Accueil (`home_dashboard.dart`), avec une phrase
  /// d'explication en plus — nécessaire ici puisque le lecteur doit
  /// comprendre POURQUOI deux graphiques voisins nommés « Bénéfices »
  /// donnent des montants très différents sur la même période.
  Widget _sectionHeader(String title, String explanation) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            explanation,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!['daily', 'by_category', 'by_product', 'top', 'monthly'].any(_can)) {
      return const Center(child: Text('Aucun graphique autorisé pour votre rôle dans cette section.'));
    }

    final dailyTotalCard = _can('daily') ? _dailyTotalCard() : null;
    final monthlyCard = _can('monthly') ? _monthlyCard() : null;
    final byCategoryCard = _can('by_category') ? _byCategoryCard() : null;
    final byProductCard = _can('by_product') ? _byProductCard() : null;
    final topCard = _can('top') ? _topCard() : null;

    if (!widget.groupNetVsGross) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ?dailyTotalCard,
          ?byCategoryCard,
          ?byProductCard,
          ?topCard,
          ?monthlyCard,
        ],
      );
    }

    final netCards = [dailyTotalCard, monthlyCard].whereType<Widget>().toList();
    final grossCards = [byCategoryCard, byProductCard, topCard].whereType<Widget>().toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (netCards.isNotEmpty) ...[
          _sectionHeader(
            'BÉNÉFICE NET',
            'Marge brute moins toutes les dépenses et les pertes enregistrées.',
          ),
          ...netCards,
          const SizedBox(height: 8),
        ],
        if (grossCards.isNotEmpty) ...[
          _sectionHeader(
            'MARGE BRUTE',
            'Recette moins coût d\'achat uniquement — les dépenses générales ne peuvent pas être réparties par catégorie ou produit, donc ces montants ne se comparent pas directement au bénéfice net ci-dessus.',
          ),
          ...grossCards,
        ],
      ],
    );
  }

  Widget _dailyTotalCard() {
    return _card(
      title: widget.titles.dailyTotal,
      controls: [_pickWeekButton()],
      child: _futureChart(_totalFuture, (chart) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (chart.weekStart.isNotEmpty)
                    Expanded(
                      child: Text(
                        _weekAnchors.length > 1
                            ? weekFilterLabel(_weekAnchors)
                            : 'Semaine du ${_dayFormat.format(DateTime.parse(chart.weekStart))} au ${_dayFormat.format(DateTime.parse(chart.weekEnd))}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  WeekTotalBadge(total: chart.total, color: widget.palette.dailyTotal),
                ],
              ),
            ),
            WeeklyBarChartWidget(
              series: chart.series,
              baseColor: widget.palette.dailyTotal,
            ),
          ],
        );
      }),
    );
  }

  Widget _byCategoryCard() {
    return _card(
      title: widget.titles.dailyByCategory,
      controls: [
        if (!_can('daily')) _pickWeekButton(),
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
      child: _futureChart(_byCategoryFuture, (chart) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: WeekTotalBadge(total: chart.total, color: widget.palette.dailyByCategory),
            ),
            WeeklyBarChartWidget(
              series: chart.series,
              baseColor: widget.palette.dailyByCategory,
            ),
          ],
        );
      }),
    );
  }

  Widget _byProductCard() {
    return _card(
      title: widget.titles.dailyByProduct,
      controls: [
        if (!_can('daily') && !_can('by_category')) _pickWeekButton(),
        if (_products.isNotEmpty)
          _ProductFilterField(
            products: _products,
            selectedIds: _selectedProductIds,
            onChanged: _toggleProductSelection,
          )
        else
          const Text('Aucun produit au catalogue'),
      ],
      // Montant total des recettes des produits vendus selon la sélection
      // du filtre Produit, en haut à droite — demande utilisateur du
      // 2026-09-24, même `WeekTotalBadge` que le graphique par catégorie.
      child: _futureChart(_byProductFuture, (chart) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: WeekTotalBadge(total: chart.total, color: widget.palette.dailyByProduct),
            ),
            WeeklyBarChartWidget(
              series: chart.series,
              baseColor: widget.palette.dailyByProduct,
            ),
          ],
        );
      }),
    );
  }

  Widget _topCard() {
    return _card(
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
      // Montant total de toutes les recettes/bénéfices de l'année
      // sélectionnée (filtre Année de `GraphiquesPage`), en haut à
      // droite — demande utilisateur du 2026-09-25. Réutilise
      // `_monthlyFuture` (déjà chargé pour la carte "mensuelle"
      // ci-dessous, même année) plutôt qu'un nouvel appel réseau.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _futureChart(
            _monthlyFuture,
            (monthly) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: WeekTotalBadge(total: monthly.total, color: widget.palette.top),
            ),
          ),
          _futureChart(
            _topFuture,
            (chart) => RankingBarChartWidget(
              items: chart.items,
              color: widget.palette.top,
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthlyCard() {
    return _card(
      title: widget.titles.monthly,
      child: _futureChart(
        _monthlyFuture,
        (chart) => MonthlyLineChartWidget(
          months: chart.months,
          color: widget.palette.monthly,
        ),
      ),
    );
  }
}

/// Filtre Produit de « Recettes/Bénéfices journaliers par produit » — sélection
/// multiple avec réinitialisation (demande utilisateur du 2026-09-22), même
/// principe que `_CategoryFilterField` (lib/stock/stock_page.dart) : un champ
/// cliquable ouvrant un dialogue à cases à cocher, plus adapté qu'une rangée
/// de puces vu le nombre de produits possible au catalogue.
class _ProductFilterField extends StatelessWidget {
  const _ProductFilterField({
    required this.products,
    required this.selectedIds,
    required this.onChanged,
  });

  final List<Product> products;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>> onChanged;

  Future<void> _open(BuildContext context) async {
    var working = Set<String>.from(selectedIds);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Filtrer par produit'),
          content: SizedBox(
            width: 360,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final product in products)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: working.contains(product.id),
                    title: Text(product.name),
                    onChanged: (checked) => setDialogState(() {
                      if (checked ?? false) {
                        working.add(product.id);
                      } else {
                        working.remove(product.id);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setDialogState(() => working = {}),
              child: const Text('Réinitialiser'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(selectedIds),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(working),
              child: const Text('Appliquer'),
            ),
          ],
        ),
      ),
    );
    if (result != null) onChanged(result);
  }

  String get _label {
    if (selectedIds.isEmpty) return 'Tous les produits';
    if (selectedIds.length == 1) {
      return products.firstWhere((p) => p.id == selectedIds.first, orElse: () => products.first).name;
    }
    return '${selectedIds.length} produits sélectionnés';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () => _open(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Produit',
          isDense: true,
          prefixIcon: const Icon(Icons.filter_list),
          suffixIcon: selectedIds.isEmpty
              ? const Icon(Icons.arrow_drop_down)
              : IconButton(
                  tooltip: 'Réinitialiser le filtre',
                  icon: const Icon(Icons.clear),
                  onPressed: () => onChanged({}),
                ),
        ),
        child: Text(_label, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}
