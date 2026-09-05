import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../catalog/models.dart';
import 'purchasing_models.dart';
import 'purchasing_repository.dart';

class _DraftLine {
  _DraftLine(this.product, this.quantity, this.unitPrice);
  final Product product;
  double quantity;
  double unitPrice;
}

class PurchaseFormPage extends StatefulWidget {
  const PurchaseFormPage({super.key, required this.repository, required this.suppliers, required this.products});

  final PurchasingRepository repository;
  final List<Supplier> suppliers;
  final List<Product> products;

  @override
  State<PurchaseFormPage> createState() => _PurchaseFormPageState();
}

class _PurchaseFormPageState extends State<PurchaseFormPage> {
  String? _supplierId;
  final List<_DraftLine> _lines = [];
  bool _isSubmitting = false;

  double get _total => _lines.fold(0, (sum, l) => sum + l.quantity * l.unitPrice);

  Future<void> _addLine() async {
    final chosen = await showDialog<Product>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Ajouter un produit'),
        children: [
          for (final product in widget.products)
            SimpleDialogOption(onPressed: () => Navigator.of(context).pop(product), child: Text(product.name)),
        ],
      ),
    );
    if (chosen == null) return;
    setState(() => _lines.add(_DraftLine(chosen, 1, chosen.purchasePrice ?? 0)));
  }

  Future<void> _submit() async {
    if (_lines.isEmpty) return;
    setState(() => _isSubmitting = true);
    try {
      await widget.repository.createPurchase(
        supplierId: _supplierId,
        items: _lines.map((l) => {'productId': l.product.id, 'quantity': l.quantity, 'unitPrice': l.unitPrice}).toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvel achat')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              initialValue: _supplierId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Fournisseur (optionnel)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Aucun')),
                for (final supplier in widget.suppliers) DropdownMenuItem(value: supplier.id, child: Text(supplier.name)),
              ],
              onChanged: (value) => setState(() => _supplierId = value),
            ),
          ),
          Expanded(
            child: _lines.isEmpty
                ? const Center(child: Text('Aucun article — ajoutez-en un avec le bouton +'))
                : ListView(
                    children: [
                      for (final line in _lines)
                        ListTile(
                          title: Text(line.product.name),
                          subtitle: Row(
                            children: [
                              SizedBox(
                                width: 80,
                                child: TextFormField(
                                  initialValue: line.quantity.toStringAsFixed(0),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: 'Qté'),
                                  onChanged: (v) => setState(() => line.quantity = double.tryParse(v) ?? line.quantity),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 100,
                                child: TextFormField(
                                  initialValue: line.unitPrice.toStringAsFixed(0),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(labelText: "Prix d'achat"),
                                  onChanged: (v) => setState(() => line.unitPrice = double.tryParse(v) ?? line.unitPrice),
                                ),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() => _lines.remove(line)),
                          ),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const Spacer(),
                    Text('${_total.toStringAsFixed(0)} FCFA', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _isSubmitting || _lines.isEmpty ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Créer la commande'),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addLine, child: const Icon(Icons.add)),
    );
  }
}
