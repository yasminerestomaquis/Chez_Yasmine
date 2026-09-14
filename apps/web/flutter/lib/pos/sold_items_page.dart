import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../common/formatting.dart';
import 'pos_models.dart';
import 'pos_repository.dart';

final _timeFormat = DateFormat('HH:mm');
final _isoDateFormat = DateFormat('yyyy-MM-dd');

String _formatQuantity(double quantity) =>
    quantity == quantity.truncateToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toString();

/// Listing des ventes du jour avec correction possible (nombre de produits
/// vendus, mode de paiement) — bouton partagé entre Caisse (`pos_page.dart`)
/// et l'écran Addition (`table_order_page.dart`), demande utilisateur du
/// 2026-09-14, voir docs/api/pos.md (« Correction d'une vente déjà
/// enregistrée »).
class SoldItemsPage extends StatefulWidget {
  const SoldItemsPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<SoldItemsPage> createState() => _SoldItemsPageState();
}

class _SoldItemsPageState extends State<SoldItemsPage> {
  late final PosRepository _repository = PosRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late Future<List<SaleResult>> _future = _load();

  Future<List<SaleResult>> _load() =>
      _repository.listForDay(_isoDateFormat.format(DateTime.now()));

  void _reload() {
    final future = _load();
    future.ignore(); // voir docs/api/reports.md — évite une "unhandled error" parasite sous flutter_test.
    setState(() => _future = future);
  }

  Future<void> _editQuantity(SaleResult sale, SaleItemResult item) async {
    final controller = TextEditingController(
      text: _formatQuantity(item.quantity),
    );
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
            final value = double.tryParse(
              controller.text.trim().replaceAll(',', '.'),
            );
            if (value != null && value > 0) Navigator.of(context).pop(value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(
                controller.text.trim().replaceAll(',', '.'),
              );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur réseau — quantité non modifiée')),
      );
    }
  }

  /// Annulation complète d'une vente (restitue le stock, efface le crédit
  /// client le cas échéant) — jusqu'ici le seul point d'entrée était l'API
  /// (`PosRepository.refund`, `SalesService.refund`), sans bouton dans
  /// l'application ; ajouté ici à la demande de l'utilisateur (2026-09-14,
  /// vérification en conditions réelles), même emplacement que les
  /// corrections de quantité/paiement ci-dessus.
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rembourser'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.refund(sale.id);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur réseau — vente non remboursée')),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur réseau — mode de paiement non modifié'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Produits vendus')),
      body: FutureBuilder<List<SaleResult>>(
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
          // Une vente remboursée reste dans l'historique mais ne se corrige
          // plus (SalesController.updateItemQuantity/updatePaymentMethod la
          // refusent de toute façon) — inutile de l'afficher ici.
          final sales = snapshot.data!
              .where((s) => s.voidedAt == null)
              .toList();
          if (sales.isEmpty) {
            return const Center(child: Text("Aucune vente aujourd'hui."));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: sales.length,
            itemBuilder: (context, index) {
              final sale = sales[index];
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
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Rembourser cette vente',
                                icon: const Icon(
                                  Icons.undo_outlined,
                                  size: 20,
                                ),
                                onPressed: () => _refund(sale),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Divider(height: 16),
                      for (final item in sale.items)
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
                            payment.method == 'cash'
                                ? Icons.payments_outlined
                                : Icons.phone_iphone_outlined,
                            size: 20,
                          ),
                          title: Text(
                            paymentMethodLabels[payment.method] ??
                                payment.method,
                          ),
                          subtitle: Text('${formatAmount(payment.amount)} FCFA'),
                          trailing:
                              (payment.method == 'cash' ||
                                  payment.method == 'mobile_money')
                              ? IconButton(
                                  tooltip: 'Modifier le mode de paiement',
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      _editPaymentMethod(sale, payment),
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
