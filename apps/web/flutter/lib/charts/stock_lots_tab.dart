import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import 'chart_models.dart';
import 'charts_repository.dart';

/// Palette dédiée à ce sous-module : dominante vert (traçabilité / stock),
/// délibérément distincte des palettes bleu/violet de Recettes et Bénéfices —
/// reprend la demande du fichier de référence ("dominante vert foncé / vert,
/// avec des touches de bleu, orange et rouge pour les statuts").
class _StockPalette {
  static const darkGreen = Color(0xFF1B5E20);
  static const green = Color(0xFF2E7D32);
  static const paleGreen = Color(0xFFE8F5E9);
  static const borderGreen = Color(0xFFC8E6C9);
  static const grey = Color(0xFF9E9E9E);
  static const background = Color(0xFFF4FBF5);
}

/// Sous-module "Stock" du module Graphiques : fiche de lots FIFO d'un
/// produit (maquette demandée — voir PROMPT et docs/api/charts.md pour la
/// logique de reconstruction des lots à partir de l'historique des
/// `StockMovement`, sans schéma de lot dédié).
///
/// Contrairement à `MetricChartsTab` (Recettes / Bénéfices), cet onglet
/// n'est PAS piloté par le filtre Année de `GraphiquesPage` : les lots FIFO
/// représentent l'état COURANT du stock, pas une période — un lot reçu il y
/// a plusieurs années peut rester actif aujourd'hui, et "l'année 2024 du
/// stock" n'a pas de sens métier à afficher isolément.
class StockLotsTab extends StatefulWidget {
  const StockLotsTab({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<StockLotsTab> createState() => _StockLotsTabState();
}

class _StockLotsTabState extends State<StockLotsTab> {
  late final ChartsRepository _charts = ChartsRepository(ApiClient(), widget.establishmentId);
  late final CatalogRepository _catalog = CatalogRepository(ApiClient(), widget.establishmentId);
  static final DateFormat _dayFormat = DateFormat('dd/MM/yyyy');

  List<Product> _products = [];
  String? _productId;
  bool _historyTabSelected = false;
  Future<StockLotsChart>? _lotsFuture;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await _catalog.listProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _productId = products.isNotEmpty ? products.first.id : null;
      });
      if (_productId != null) _reload();
    } catch (_) {
      // Le FutureBuilder du tableau affiche déjà son propre état d'erreur
      // réseau ; ici il n'y a simplement pas de produit à proposer.
    }
  }

  void _reload() {
    // `..ignore()` avant `setState` : même garde que MetricChartsTab contre
    // un rejet "unhandled" en test (flutter_test répond quasi instantanément).
    final future = _charts.getStockLots(productId: _productId!);
    future.ignore();
    setState(() => _lotsFuture = future);
  }

  String _formatQuantity(double value) => value == value.roundToDouble() ? value.toInt().toString() : '$value';

  Widget _statusBadge(StockLot lot) {
    final color = lot.isActive ? _StockPalette.green : _StockPalette.grey;
    final label = lot.isActive ? 'Actif' : 'Épuisé';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _tabButton(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        margin: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: selected ? _StockPalette.darkGreen : Colors.transparent, width: 3)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? _StockPalette.darkGreen : Colors.black54,
          ),
        ),
      ),
    );
  }

  Widget _lotsTable(List<StockLot> lots) {
    if (lots.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('Aucun lot à afficher pour ce produit')),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(_StockPalette.paleGreen),
        columns: const [
          DataColumn(label: Text('Lot')),
          DataColumn(label: Text('Date réception')),
          DataColumn(label: Text('Quantité reçue'), numeric: true),
          DataColumn(label: Text('Consommé'), numeric: true),
          DataColumn(label: Text('Restant'), numeric: true),
          DataColumn(label: Text('Statut')),
        ],
        rows: [
          for (final lot in lots)
            DataRow(
              cells: [
                DataCell(Text(lot.code, style: const TextStyle(fontWeight: FontWeight.bold))),
                DataCell(Text(_dayFormat.format(lot.receivedAt))),
                DataCell(Text(_formatQuantity(lot.receivedQuantity))),
                DataCell(Text(_formatQuantity(lot.consumedQuantity))),
                DataCell(Text(_formatQuantity(lot.remainingQuantity))),
                DataCell(_statusBadge(lot)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _totalCard(StockLotsChart chart) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _StockPalette.paleGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _StockPalette.borderGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL ${chart.productName.toUpperCase()} (LOTS ACTIFS)',
            style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5, color: _StockPalette.darkGreen),
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatQuantity(chart.totalActiveUnits)} unités',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _StockPalette.darkGreen),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _StockPalette.background,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: _StockPalette.borderGreen),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('📦 ', style: TextStyle(fontSize: 20)),
                      Expanded(
                        child: Text(
                          'Détail d\'un produit',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: _StockPalette.darkGreen, fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton(
                        onPressed: _products.isEmpty ? null : () => setState(() => _historyTabSelected = true),
                        child: const Text('Voir tous les lots →'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_products.isNotEmpty)
                    DropdownButton<String?>(
                      value: _productId,
                      underline: const SizedBox.shrink(),
                      items: [for (final product in _products) DropdownMenuItem(value: product.id, child: Text(product.name))],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _productId = value;
                          _historyTabSelected = false;
                        });
                        _reload();
                      },
                    )
                  else
                    const Text('Aucun produit au catalogue'),
                  const SizedBox(height: 12),
                  if (_productId == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('Ajoutez un produit au catalogue pour suivre son stock par lots')),
                    )
                  else
                    FutureBuilder<StockLotsChart>(
                      future: _lotsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snapshot.hasError) {
                          final message =
                              snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: Text(message)),
                          );
                        }
                        final chart = snapshot.data!;
                        final activeCount = chart.activeLots.length;
                        final historyCount = chart.historyLots.length;
                        final visibleLots = _historyTabSelected ? chart.historyLots : chart.activeLots;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _tabButton('Lots actifs ($activeCount)', !_historyTabSelected,
                                    () => setState(() => _historyTabSelected = false)),
                                _tabButton(
                                    'Historique ($historyCount)', _historyTabSelected, () => setState(() => _historyTabSelected = true)),
                              ],
                            ),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            _lotsTable(visibleLots),
                            _totalCard(chart),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
