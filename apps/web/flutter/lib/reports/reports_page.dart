import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../common/formatting.dart';
import 'report_models.dart';
import 'reports_repository.dart';

const _periodLabels = {'day': 'Jour', 'week': 'Semaine', 'month': 'Mois', 'year': 'Année'};

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late final ReportsRepository _repository = ReportsRepository(ApiClient(), widget.establishmentId);
  String _period = 'day';
  late Future<ReportSummary> _future = _repository.getSummary(period: _period);

  void _changePeriod(String period) {
    // future.ignore() marks the future as intentionally observed the instant
    // it's created, rather than relying solely on FutureBuilder to subscribe
    // on its next rebuild — if the future rejects before that rebuild
    // happens, the Dart runtime otherwise reports it as an unhandled error
    // for that one turn regardless of what subscribes afterwards. This
    // doesn't change what FutureBuilder itself sees below (a Future can have
    // any number of independent listeners); it only prevents that spurious
    // report.
    final future = _repository.getSummary(period: period);
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
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer'))],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _indicator(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapports'),
        actions: [IconButton(tooltip: 'Exporter en CSV', icon: const Icon(Icons.download_outlined), onPressed: _exportCsv)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              segments: [for (final entry in _periodLabels.entries) ButtonSegment(value: entry.key, label: Text(entry.value))],
              selected: {_period},
              onSelectionChanged: (selection) => _changePeriod(selection.first),
            ),
          ),
          Expanded(
            child: FutureBuilder<ReportSummary>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
                  return Center(child: Text(message));
                }
                final s = snapshot.data!;
                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _indicator("Chiffre d'affaires", '${formatAmount(s.revenue)} FCFA'),
                            _indicator('Nombre de ventes', '${s.salesCount}'),
                            _indicator('Remises', '${formatAmount(s.discountTotal)} FCFA'),
                            _indicator('Marge brute', '${formatAmount(s.grossMargin)} FCFA'),
                            _indicator('Dépenses', '${formatAmount(s.expenses)} FCFA'),
                            _indicator('Pertes', '${formatAmount(s.losses)} FCFA'),
                            const Divider(),
                            _indicator('Bénéfice net (estimé)', '${formatAmount(s.netProfit)} FCFA'),
                            _indicator('Créances clients', '${formatAmount(s.receivables)} FCFA'),
                            _indicator('Produits en alerte de stock', '${s.lowStockCount}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (s.topProducts.isNotEmpty) ...[
                      const Text('Produits les plus vendus', style: TextStyle(fontWeight: FontWeight.bold)),
                      for (final p in s.topProducts)
                        ListTile(
                          dense: true,
                          title: Text(p.name),
                          trailing: Text('${p.quantity.toStringAsFixed(0)} — ${formatAmount(p.revenue)} FCFA'),
                        ),
                      const SizedBox(height: 16),
                    ],
                    if (s.productProfitability.isNotEmpty) ...[
                      const Text('Bénéfice par produit', style: TextStyle(fontWeight: FontWeight.bold)),
                      for (final p in s.productProfitability)
                        ListTile(
                          dense: true,
                          title: Text(p.name),
                          subtitle: Text('${p.quantity.toStringAsFixed(0)} vendu(s) — CA ${formatAmount(p.revenue)} FCFA'),
                          trailing: Text('${formatAmount(p.profit)} FCFA'),
                        ),
                      const SizedBox(height: 16),
                    ],
                    if (s.serverPerformance.isNotEmpty) ...[
                      const Text('Performance des serveurs', style: TextStyle(fontWeight: FontWeight.bold)),
                      for (final perf in s.serverPerformance)
                        ListTile(
                          dense: true,
                          title: Text(perf.name),
                          trailing: Text('${perf.salesCount} ventes — ${formatAmount(perf.total)} FCFA'),
                        ),
                    ],
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
