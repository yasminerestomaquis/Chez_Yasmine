import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../common/formatting.dart';
import 'pos_models.dart';
import 'pos_repository.dart';

final _dayHeaderFormat = DateFormat('dd/MM/yyyy');
final _timeFormat = DateFormat('HH:mm');
final _isoDateFormat = DateFormat('yyyy-MM-dd');

String _formatQuantity(double quantity) =>
    quantity == quantity.truncateToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toString();

bool _isPlatsCategory(Product p) => p.hasVariablePricing;
bool _isBoissonsCategory(Product p) => p.hasCasePricing;

/// Filtre les ventes non remboursées de [sales] aux lignes dont le produit
/// est dans [matchingProductIds], et calcule le total (qté × prix unitaire)
/// de ces seules lignes — logique métier pure, testable sans widget ni
/// réseau (voir `test/category_sold_items_page_test.dart`).
({List<({SaleResult sale, List<SaleItemResult> items})> matches, double total})
    matchingSalesWithTotal(List<SaleResult> sales, Set<String> matchingProductIds) {
  final matches = <({SaleResult sale, List<SaleItemResult> items})>[];
  var total = 0.0;
  for (final sale in sales) {
    // Une vente remboursée reste dans l'historique mais ne se corrige plus
    // (SalesController.updateItemQuantity/updatePaymentMethod la refusent
    // de toute façon) — inutile de l'afficher ici.
    if (sale.voidedAt != null) continue;
    final items = sale.items.where((i) => matchingProductIds.contains(i.productId)).toList();
    if (items.isEmpty) continue;
    for (final item in items) {
      total += item.quantity * item.unitPrice;
    }
    matches.add((sale: sale, items: items));
  }
  return (matches: matches, total: total);
}

/// Listing des ventes d'une date choisie, filtré aux catégories d'un groupe
/// donné (Plats africains/Poissons/Poulets ou Bières/Vins/Sucreries — même
/// découpage que les exports Excel de Rapports, voir `reports_page.dart`),
/// avec le total en gras en tête de liste et une correction possible
/// (quantité, mode de paiement, remboursement complet) sur chaque ligne.
///
/// Remplace `SoldItemsPage` en Caisse et dans l'écran Addition (demande
/// utilisateur du 2026-09-15) : deux boutons dédiés (« Plats vendus » /
/// « Boissons vendues ») plutôt qu'un listing unique et non filtré — la
/// capacité de correction déjà présente dans `SoldItemsPage` est reprise à
/// l'identique ici, sur demande explicite de l'utilisateur, plutôt que
/// perdue. Voir docs/api/pos.md.
class CategorySoldItemsPage extends StatefulWidget {
  const CategorySoldItemsPage({
    super.key,
    required this.establishmentId,
    required this.title,
    required this.categoryFilter,
    required this.emptyMessage,
  });

  factory CategorySoldItemsPage.plats({Key? key, required String establishmentId}) =>
      CategorySoldItemsPage(
        key: key,
        establishmentId: establishmentId,
        title: 'Plats vendus',
        categoryFilter: _isPlatsCategory,
        emptyMessage: 'Aucune vente Plats africains/Poissons/Poulets ce jour-là.',
      );

  factory CategorySoldItemsPage.boissons({Key? key, required String establishmentId}) =>
      CategorySoldItemsPage(
        key: key,
        establishmentId: establishmentId,
        title: 'Boissons vendues',
        categoryFilter: _isBoissonsCategory,
        emptyMessage: 'Aucune vente Bières/Vins/Sucreries ce jour-là.',
      );

  final String establishmentId;
  final String title;
  final bool Function(Product) categoryFilter;
  final String emptyMessage;

  @override
  State<CategorySoldItemsPage> createState() => _CategorySoldItemsPageState();
}

class _CategorySoldItemsPageState extends State<CategorySoldItemsPage> {
  late final CatalogRepository _catalog = CatalogRepository(ApiClient(), widget.establishmentId);
  late final PosRepository _repository = PosRepository(ApiClient(), widget.establishmentId);

  DateTime _date = DateTime.now();
  List<Product> _products = [];
  List<SaleResult> _sales = [];
  late Future<void> _future = _load();

  Future<void> _load() async {
    final (products, sales) = await (
      _catalog.listProducts(),
      _repository.listForDay(_isoDateFormat.format(_date)),
    ).wait;
    _products = products;
    _sales = sales;
  }

  void _reload() {
    final future = _load();
    future.ignore(); // voir docs/api/reports.md — évite une "unhandled error" parasite sous flutter_test.
    setState(() => _future = future);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Date des ventes à afficher',
    );
    if (picked == null) return;
    setState(() {
      _date = picked;
      _future = _load();
    });
  }

  Future<void> _editQuantity(SaleResult sale, SaleItemResult item) async {
    final controller = TextEditingController(text: _formatQuantity(item.quantity));
    final newQuantity = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Modifier la quantité — ${item.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Quantité'),
          onSubmitted: (_) {
            final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
            if (value != null && value > 0) Navigator.of(context).pop(value);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
              if (value == null || value <= 0) return;
              Navigator.of(context).pop(value);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (newQuantity == null || newQuantity == item.quantity) return;
    try {
      await _repository.updateItemQuantity(sale.id, item.id, newQuantity);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur réseau — quantité non modifiée')),
      );
    }
  }

  Future<void> _editPaymentMethod(SaleResult sale, PaymentResult payment) async {
    final method = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Modifier le mode de paiement'),
        children: [
          for (final m in const ['cash', 'mobile_money'])
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(m),
              child: Text(paymentMethodLabels[m] ?? m),
            ),
        ],
      ),
    );
    if (method == null || method == payment.method) return;
    try {
      await _repository.updatePaymentMethod(sale.id, payment.id, method);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur réseau — mode de paiement non modifié')),
      );
    }
  }

  /// Annule la vente entière (restitue le stock), pas seulement les lignes
  /// affichées ici — une vente mêlant par exemple une boisson et un plat
  /// reste remboursée dans son intégralité, le montant annoncé dans la
  /// confirmation (`sale.total`) le reflète fidèlement.
  Future<void> _refund(SaleResult sale) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rembourser cette vente ?'),
        content: Text(
          'La vente de ${_timeFormat.format(sale.createdAt.toLocal())} '
          '(${formatAmount(sale.total)} FCFA) sera annulée et le stock '
          'restitué. Cette action est irréversible.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Rembourser')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.refund(sale.id);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur réseau — vente non remboursée')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title} — ${_dayHeaderFormat.format(_date)}'),
        actions: [
          IconButton(
            tooltip: 'Changer la date',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: _pickDate,
          ),
        ],
      ),
      body: FutureBuilder<void>(
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

          final matchingProductIds = _products.where(widget.categoryFilter).map((p) => p.id).toSet();
          final (:matches, :total) = matchingSalesWithTotal(_sales, matchingProductIds);

          if (matches.isEmpty) {
            return Center(child: Text(widget.emptyMessage));
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Total : ${formatAmount(total)} FCFA',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12).copyWith(bottom: 12),
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final (:sale, :items) = matches[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _timeFormat.format(sale.createdAt.toLocal()),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${formatAmount(sale.total)} FCFA',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    IconButton(
                                      tooltip: 'Rembourser cette vente',
                                      icon: const Icon(Icons.undo_outlined, size: 20),
                                      onPressed: () => _refund(sale),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            for (final item in items)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(item.name),
                                subtitle: Text(
                                  '${_formatQuantity(item.quantity)} × ${formatAmount(item.unitPrice)} FCFA',
                                ),
                                trailing: IconButton(
                                  tooltip: 'Modifier la quantité',
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  onPressed: () => _editQuantity(sale, item),
                                ),
                              ),
                            for (final payment in sale.payments)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                leading: Icon(
                                  payment.method == 'cash' ? Icons.payments_outlined : Icons.phone_iphone_outlined,
                                  size: 20,
                                ),
                                title: Text(paymentMethodLabels[payment.method] ?? payment.method),
                                subtitle: Text('${formatAmount(payment.amount)} FCFA'),
                                trailing: (payment.method == 'cash' || payment.method == 'mobile_money')
                                    ? IconButton(
                                        tooltip: 'Modifier le mode de paiement',
                                        icon: const Icon(Icons.edit_outlined, size: 20),
                                        onPressed: () => _editPaymentMethod(sale, payment),
                                      )
                                    : null,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
