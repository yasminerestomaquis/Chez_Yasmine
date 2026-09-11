import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../charts/chart_models.dart';
import '../charts/charts_repository.dart';
import '../charts/weekly_bar_chart.dart';
import '../common/browser_download.dart';
import '../common/formatting.dart';
import '../customers/customers_page.dart';
import '../losses/losses_page.dart';
import '../pos/pos_repository.dart';
import '../purchasing/purchasing_models.dart';
import '../purchasing/purchasing_repository.dart';
import '../stock/stock_page.dart';
import '../theme/app_theme.dart';
import 'report_models.dart';
import 'reports_repository.dart';

final _orderDateFormat = DateFormat('dd/MM/yyyy');
final _isoDateFormat = DateFormat('yyyy-MM-dd');

const _periodLabels = {
  'day': 'Jour',
  'week': 'Semaine',
  'month': 'Mois',
  'year': 'Année',
};
const _previousPeriodLabels = {
  'day': 'à hier',
  'week': 'à la semaine précédente',
  'month': 'au mois précédent',
  'year': "à l'année précédente",
};
const _medals = ['🥇', '🥈', '🥉'];

/// Bundle chargé en un seul aller-retour logique pour éviter les rebuilds en
/// cascade : le résumé de la période choisie (obligatoire), le résumé de la
/// période équivalente précédente (comparaison — simple complément visuel,
/// jamais bloquant si l'appel échoue) et le graphique hebdomadaire des
/// recettes déjà exposé par le module Graphiques (`ChartsService.weeklyTotal`,
/// réutilisé tel quel — aucune nouvelle route).
class _ReportsData {
  _ReportsData({
    required this.current,
    required this.previous,
    required this.weekly,
  });
  final ReportSummary current;
  final ReportSummary? previous;
  final WeeklyChart? weekly;
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late final ReportsRepository _repository = ReportsRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final ChartsRepository _charts = ChartsRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final PurchasingRepository _purchasing = PurchasingRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final CatalogRepository _catalog = CatalogRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final PosRepository _pos = PosRepository(
    ApiClient(),
    widget.establishmentId,
  );
  String _period = 'day';
  late Future<_ReportsData> _future = _load(_period);

  Future<_ReportsData> _load(String period) async {
    final current = await _repository.getSummary(period: period);
    // Période de comparaison : même durée que la période choisie, immédiatement
    // avant — générique (fonctionne pour jour/semaine/mois/année sans
    // recalculer de bornes calendaires) et construite à partir de `from`/`to`
    // déjà renvoyés par l'API, aucune nouvelle route serveur.
    final duration = current.to.difference(current.from);
    ReportSummary? previous;
    try {
      previous = await _repository.getSummary(
        from: current.from.subtract(duration).toIso8601String(),
        to: current.from.toIso8601String(),
      );
    } catch (_) {
      // Comparaison à la période précédente : simple complément d'affichage, jamais bloquant.
    }
    WeeklyChart? weekly;
    try {
      weekly = await _charts.getWeekly(metric: 'revenue');
    } catch (_) {
      // Graphique d'évolution : simple complément d'affichage, jamais bloquant.
    }
    return _ReportsData(current: current, previous: previous, weekly: weekly);
  }

  void _changePeriod(String period) {
    // Même précaution que l'ancienne implémentation : observer le futur dès
    // sa création pour éviter un rejet non géré si `HttpOverrides` (tests)
    // répond avant que `FutureBuilder` ne s'y réabonne au prochain rebuild.
    final future = _load(period);
    future.ignore();
    setState(() {
      _period = period;
      _future = future;
    });
  }

  Future<void> _exportCsv() async {
    try {
      final csv = await _repository.exportSummaryCsv(period: _period);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export CSV'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(child: SelectableText(csv)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Exporte le listing d'une commande d'achat (Bières/Vins/Sucreries — seules
  /// catégories qu'Achats accepte, voir `docs/api/purchasing.md`), retrouvée
  /// par N° de commande + date, dans la même présentation que l'écran
  /// Historique d'Achats. Réutilise `PurchasingRepository.listPurchases`
  /// (déjà existant, filtré côté client) — aucune nouvelle route serveur.
  Future<void> _exportPurchaseOrderDialog() async {
    final orderNumberController = TextEditingController();
    var selectedDate = DateTime.now();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Exporter une commande d\'achat'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: orderNumberController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'N° de la commande *',
                  ),
                  validator: (v) => int.tryParse((v ?? '').trim()) == null
                      ? 'N° invalide'
                      : null,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      helpText: 'Date de la commande',
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    'Date : ${_orderDateFormat.format(selectedDate)}',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text('Rechercher'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final orderNumber = int.parse(orderNumberController.text.trim());
    try {
      final purchases = await _purchasing.listPurchases();
      final matches = purchases
          .where(
            (p) =>
                p.orderNumber == orderNumber &&
                p.orderDate.year == selectedDate.year &&
                p.orderDate.month == selectedDate.month &&
                p.orderDate.day == selectedDate.day,
          )
          .toList();
      if (!mounted) return;
      if (matches.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Aucune commande n°$orderNumber trouvée à cette date.',
            ),
          ),
        );
        return;
      }
      final purchase = matches.length == 1
          ? matches.first
          : await _pickAmongPurchases(matches);
      if (purchase == null) return;
      await _showPurchaseCsv(purchase);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Un même N° de commande + date peut en théorie correspondre à plusieurs
  /// fournisseurs (`orderNumber` n'est jamais contraint en unicité côté
  /// serveur, voir `docs/api/purchasing.md`) — désambiguïsation par fournisseur.
  Future<Purchase?> _pickAmongPurchases(List<Purchase> matches) {
    return showDialog<Purchase>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Plusieurs commandes correspondent'),
        children: [
          for (final p in matches)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(p),
              child: Text(
                'N°${p.orderNumber} — ${p.supplier?.name ?? 'Sans fournisseur'}',
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showPurchaseCsv(Purchase purchase) async {
    final rows = <String>[
      '"Commande n°${purchase.orderNumber}"',
      '"Date","${_orderDateFormat.format(purchase.orderDate)}"',
      '"Fournisseur","${purchase.supplier?.name ?? 'Sans fournisseur'}"',
      '',
      '"Produit","Prix par casier (FCFA)","Casiers commandés","Total (FCFA)"',
      for (final item in purchase.items)
        '"${item.productName}",${item.purchasePricePerCase.toStringAsFixed(0)},'
            '${item.casesOrdered.toStringAsFixed(0)},${item.lineTotal.toStringAsFixed(0)}',
      '"Total","","${purchase.totalCases.toStringAsFixed(0)}","${purchase.total.toStringAsFixed(0)}"',
    ];
    final csv = rows.join('\n');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Commande n°${purchase.orderNumber} — export CSV'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(child: SelectableText(csv)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  /// Listing des produits vendus des catégories Bières/Vins/Sucreries
  /// (`hasCasePricing`) pour un jour choisi par l'utilisateur, affiché
  /// directement dans l'application — construit côté client à partir de
  /// deux routes déjà existantes (`GET .../products` et
  /// `GET .../sales?day=`), sans dépendre d'un nouvel endpoint serveur.
  /// Le dialogue propose aussi « Exporter en Excel », qui réutilise
  /// `GET .../reports/beverages-sold.xlsx` (`ReportsRepository.exportBeveragesSoldExcel`).
  Future<void> _showBeveragesSoldListing() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Date des ventes à afficher',
    );
    if (picked == null) return;

    try {
      final day = _isoDateFormat.format(picked);
      final (products, sales) = await (
        _catalog.listProducts(),
        _pos.listForDay(day),
      ).wait;

      final caseProductIds = products
          .where((p) => p.hasCasePricing)
          .map((p) => p.id)
          .toSet();

      final rows =
          <({String name, int? orderNumber, double quantity, double total})>[];
      for (final sale in sales) {
        if (sale.voidedAt != null) continue;
        for (final item in sale.items) {
          if (!caseProductIds.contains(item.productId)) continue;
          rows.add((
            name: item.name,
            orderNumber: sale.orderNumber,
            quantity: item.quantity,
            total: item.quantity * item.unitPrice,
          ));
        }
      }
      final totalQuantity = rows.fold<double>(0, (sum, r) => sum + r.quantity);
      final totalAmount = rows.fold<double>(0, (sum, r) => sum + r.total);

      if (!mounted) return;
      final exportRequested = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Boissons vendues — ${_orderDateFormat.format(picked)}'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Aucune vente Bières/Vins/Sucreries ce jour-là.',
                      ),
                    )
                  : DataTable(
                      columns: const [
                        DataColumn(label: Text('Produit')),
                        DataColumn(label: Text('N° commande')),
                        DataColumn(label: Text('Qté'), numeric: true),
                        DataColumn(
                          label: Text('Montant (FCFA)'),
                          numeric: true,
                        ),
                      ],
                      rows: [
                        for (final r in rows)
                          DataRow(
                            cells: [
                              DataCell(Text(r.name)),
                              DataCell(Text(r.orderNumber?.toString() ?? '—')),
                              DataCell(Text(r.quantity.toStringAsFixed(0))),
                              DataCell(Text(formatAmount(r.total))),
                            ],
                          ),
                        DataRow(
                          cells: [
                            const DataCell(
                              Text(
                                'TOTAL',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const DataCell(Text('')),
                            DataCell(
                              Text(
                                totalQuantity.toStringAsFixed(0),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                formatAmount(totalAmount),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Fermer'),
            ),
            if (rows.isNotEmpty)
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Exporter en Excel'),
              ),
          ],
        ),
      );
      if (exportRequested == true) {
        await _downloadBeveragesSoldExcel(day, picked);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _downloadBeveragesSoldExcel(String day, DateTime picked) async {
    try {
      final result = await _repository.exportBeveragesSoldExcel(day);
      downloadBytes(
        result.bytes,
        result.filename ??
            'Boissons vendues ${DateFormat('dd-MM-yyyy').format(picked)}.xlsx',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  ({String text, bool positive})? _pctChange(double current, double? previous) {
    if (previous == null || previous == 0) return null;
    final pct = (current - previous) / previous * 100;
    final positive = pct >= 0;
    return (
      text: '${positive ? '↑ +' : '↓ -'}${pct.abs().toStringAsFixed(1)} %',
      positive: positive,
    );
  }

  ({String text, bool positive})? _absChange(int? delta) {
    if (delta == null) return null;
    final positive = delta >= 0;
    return (
      text: '${positive ? '↑ +' : '↓ -'}${delta.abs()}',
      positive: positive,
    );
  }

  Widget _kpiCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    ({String text, bool positive})? change,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (change != null)
              Text(
                change.text,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: change.positive ? AppColors.green : AppColors.alert,
                ),
              )
            else
              const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _rankedProductTile(int index, TopProduct p) {
    final rank = index < _medals.length ? _medals[index] : '${index + 1}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(rank, style: const TextStyle(fontSize: 14)),
          ),
          Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
          Text(
            '${p.quantity.toStringAsFixed(0)} — ${formatAmount(p.revenue)} F',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _profitabilityTile(TopProduct p, double maxProfit) {
    final isNegative = p.profit < 0;
    final fraction = (!isNegative && maxProfit > 0)
        ? (p.profit / maxProfit).clamp(0.0, 1.0)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${isNegative ? '' : '+'}${formatAmount(p.profit)} F',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isNegative ? AppColors.alert : AppColors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: AppColors.greenLight,
              valueColor: const AlwaysStoppedAnimation(AppColors.green),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'CA ${formatAmount(p.revenue)} F · Coût ${formatAmount(p.cost)} F',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _serverRow({
    required String server,
    required String sales,
    required String total,
    required String avg,
    bool header = false,
  }) {
    final style = header
        ? const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          )
        : const TextStyle(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              server,
              style: header
                  ? style
                  : const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(sales, textAlign: TextAlign.center, style: style),
          ),
          Expanded(
            flex: 2,
            child: Text(total, textAlign: TextAlign.right, style: style),
          ),
          Expanded(
            flex: 2,
            child: Text(
              avg,
              textAlign: TextAlign.right,
              style: header
                  ? style
                  : const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attentionRow({
    required Color color,
    required String text,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
          TextButton(onPressed: onTap, child: Text('$actionLabel →')),
        ],
      ),
    );
  }

  Widget _attentionList(ReportSummary s) {
    final items = <Widget>[];
    if (s.lowStockCount > 0) {
      items.add(
        _attentionRow(
          color: AppColors.alert,
          text:
              '${s.lowStockCount} produit${s.lowStockCount > 1 ? 's' : ''} en alerte de stock',
          actionLabel: 'Voir le stock',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  StockPage(establishmentId: widget.establishmentId),
            ),
          ),
        ),
      );
    }
    if (s.receivables > 0) {
      items.add(
        _attentionRow(
          color: AppColors.orange,
          text: '${formatAmount(s.receivables)} FCFA de créances clients',
          actionLabel: 'Voir les clients',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  CustomersPage(establishmentId: widget.establishmentId),
            ),
          ),
        ),
      );
    }
    if (s.losses > 0) {
      items.add(
        _attentionRow(
          color: AppColors.orange,
          text: '${formatAmount(s.losses)} FCFA de pertes sur la période',
          actionLabel: 'Voir les pertes',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  LossesPage(establishmentId: widget.establishmentId),
            ),
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return const Row(
        children: [
          Icon(Icons.check_circle_outline, color: AppColors.green, size: 18),
          SizedBox(width: 8),
          Text('Aucune alerte sur cette période'),
        ],
      );
    }
    return Column(children: items);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapports'),
        actions: [
          IconButton(
            tooltip: 'Boissons vendues',
            icon: const Icon(Icons.local_bar_outlined),
            onPressed: _showBeveragesSoldListing,
          ),
          PopupMenuButton<String>(
            tooltip: 'Exporter',
            icon: const Icon(Icons.download_outlined),
            onSelected: (value) {
              if (value == 'csv') _exportCsv();
              if (value == 'purchase') _exportPurchaseOrderDialog();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'csv',
                child: Text('Exporter le rapport (CSV)'),
              ),
              PopupMenuItem(
                value: 'purchase',
                child: Text('Exporter une commande d\'achat'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<String>(
              segments: [
                for (final entry in _periodLabels.entries)
                  ButtonSegment(value: entry.key, label: Text(entry.value)),
              ],
              selected: {_period},
              onSelectionChanged: (selection) => _changePeriod(selection.first),
            ),
          ),
          Expanded(
            child: FutureBuilder<_ReportsData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final message = snapshot.error is ApiException
                      ? (snapshot.error as ApiException).message
                      : '${snapshot.error}';
                  return Center(child: Text(message));
                }
                final data = snapshot.data!;
                final s = data.current;
                final prev = data.previous;
                final avgBasket = s.salesCount > 0
                    ? s.revenue / s.salesCount
                    : 0.0;
                final prevAvgBasket = (prev != null && prev.salesCount > 0)
                    ? prev.revenue / prev.salesCount
                    : null;
                final maxProfit = s.productProfitability.fold<double>(
                  0,
                  (a, p) => p.profit > a ? p.profit : a,
                );

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    // Niveau 1 — Performance : ce qui répond à "combien ai-je vendu, est-ce rentable".
                    GridView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            mainAxisExtent: 100,
                          ),
                      children: [
                        _kpiCard(
                          icon: Icons.payments_outlined,
                          label: "Chiffre d'affaires",
                          value: '${formatAmount(s.revenue)} F',
                          color: AppColors.green,
                          change: _pctChange(s.revenue, prev?.revenue),
                        ),
                        _kpiCard(
                          icon: Icons.trending_up,
                          label: 'Bénéfice net',
                          value: '${formatAmount(s.netProfit)} F',
                          color: s.netProfit >= 0
                              ? AppColors.green
                              : AppColors.alert,
                          change: _pctChange(s.netProfit, prev?.netProfit),
                        ),
                        _kpiCard(
                          icon: Icons.receipt_long_outlined,
                          label: 'Ventes',
                          value: '${s.salesCount}',
                          color: AppColors.orange,
                          change: _absChange(
                            prev != null
                                ? s.salesCount - prev.salesCount
                                : null,
                          ),
                        ),
                        _kpiCard(
                          icon: Icons.shopping_basket_outlined,
                          label: 'Panier moyen',
                          value: '${formatAmount(avgBasket)} F',
                          color: AppColors.orange,
                          change: _pctChange(avgBasket, prevAvgBasket),
                        ),
                      ],
                    ),
                    if (prev != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Comparé ${_previousPeriodLabels[_period]}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Niveau 2 — Rentabilité (vue établissement, distincte de la rentabilité par produit plus bas).
                    _sectionCard(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Rentabilité',
                      child: GridView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              mainAxisExtent: 52,
                            ),
                        children: [
                          _miniStat(
                            'Marge brute',
                            '${formatAmount(s.grossMargin)} F',
                          ),
                          _miniStat(
                            'Dépenses',
                            '${formatAmount(s.expenses)} F',
                          ),
                          _miniStat('Pertes', '${formatAmount(s.losses)} F'),
                          _miniStat(
                            'Créances',
                            '${formatAmount(s.receivables)} F',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Niveau 3 — Évolution : "comment évolue mon activité".
                    _sectionCard(
                      icon: Icons.show_chart,
                      title:
                          'Évolution du chiffre d\'affaires — semaine en cours',
                      child: data.weekly == null
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Text(
                                  'Graphique indisponible',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            )
                          : WeeklyBarChartWidget(
                              series: data.weekly!.series,
                              baseColor: AppColors.green,
                            ),
                    ),
                    const SizedBox(height: 16),

                    // Niveau 4 — Analyse : "qu'est-ce qui se vend le mieux, qu'est-ce qui rapporte".
                    if (s.topProducts.isNotEmpty) ...[
                      _sectionCard(
                        icon: Icons.emoji_events_outlined,
                        title: 'Produits les plus vendus',
                        child: Column(
                          children: [
                            for (var i = 0; i < s.topProducts.length; i++)
                              _rankedProductTile(i, s.topProducts[i]),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (s.productProfitability.isNotEmpty) ...[
                      _sectionCard(
                        icon: Icons.attach_money,
                        title: 'Rentabilité des produits',
                        child: Column(
                          children: [
                            for (final p in s.productProfitability.take(10))
                              _profitabilityTile(p, maxProfit),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Niveau 5 — Qui vend le mieux.
                    if (s.serverPerformance.isNotEmpty) ...[
                      _sectionCard(
                        icon: Icons.groups_outlined,
                        title: 'Performance des serveurs',
                        child: Column(
                          children: [
                            _serverRow(
                              server: 'Serveur',
                              sales: 'Ventes',
                              total: 'CA',
                              avg: 'Panier moyen',
                              header: true,
                            ),
                            const Divider(height: 12),
                            for (final perf in s.serverPerformance)
                              _serverRow(
                                server: perf.name,
                                sales: '${perf.salesCount}',
                                total: '${formatAmount(perf.total)} F',
                                avg:
                                    '${formatAmount(perf.salesCount > 0 ? perf.total / perf.salesCount : 0)} F',
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Niveau 6 — Quels sont mes problèmes.
                    _sectionCard(
                      icon: Icons.warning_amber_outlined,
                      title: "Points d'attention",
                      child: _attentionList(s),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
