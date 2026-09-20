import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import 'loss_models.dart';
import 'loss_pricing_choice.dart';
import 'losses_repository.dart';

/// Modifie date, produit, quantité et motif d'une perte déjà enregistrée
/// (Super Administrateur/Gérant/Serveur, `losses.edit` — demande utilisateur
/// du 2026-09-20). Retourne `true` si la perte a été modifiée.
Future<bool?> showEditLossDialog(
  BuildContext context, {
  required LossesRepository repository,
  required CatalogRepository catalogRepository,
  required Loss loss,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _EditLossDialog(repository: repository, catalogRepository: catalogRepository, loss: loss),
  );
}

class _EditLossDialog extends StatefulWidget {
  const _EditLossDialog({required this.repository, required this.catalogRepository, required this.loss});

  final LossesRepository repository;
  final CatalogRepository catalogRepository;
  final Loss loss;

  @override
  State<_EditLossDialog> createState() => _EditLossDialogState();
}

class _EditLossDialogState extends State<_EditLossDialog> {
  static final _dateFormat = DateFormat('dd/MM/yyyy');

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _quantityController = TextEditingController(
    text: widget.loss.quantity == widget.loss.quantity.roundToDouble()
        ? widget.loss.quantity.toStringAsFixed(0)
        : '${widget.loss.quantity}',
  );
  late final TextEditingController _reasonController = TextEditingController(text: widget.loss.reason ?? '');
  late final Future<List<Product>> _products = widget.catalogRepository.listProducts();
  late String _productId = widget.loss.productId;
  late DateTime _date = widget.loss.createdAt.toLocal();
  late bool _sellAsUnit = widget.loss.sellAsUnit;
  List<Product> _loaded = const [];
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Date de la perte',
    );
    if (picked == null) return;
    // On garde l'heure d'origine : seule la date change.
    setState(() => _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute, _date.second));
  }

  Product? get _selectedProduct {
    for (final p in _loaded) {
      if (p.id == _productId) return p;
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final quantity = double.parse(_quantityController.text.trim().replaceAll(',', '.'));
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.repository.updateLoss(
        widget.loss.id,
        productId: _productId,
        quantity: quantity,
        reason: _reasonController.text.trim(),
        createdAt: _date,
        sellAsUnit: _sellAsUnit && hasLotAndUnitPricing(_selectedProduct),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Erreur réseau — perte non modifiée');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier la perte'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text('Date : ${_dateFormat.format(_date)}'),
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Product>>(
                future: _products,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const Text('Impossible de charger la liste des produits.', style: TextStyle(color: Colors.red));
                  }
                  final products = snapshot.data!;
                  _loaded = products;
                  return DropdownButtonFormField<String>(
                    initialValue: products.any((p) => p.id == _productId) ? _productId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Produit *'),
                    items: products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                    onChanged: (value) => setState(() {
                      _productId = value ?? _productId;
                      _sellAsUnit = false;
                    }),
                  );
                },
              ),
              if (hasLotAndUnitPricing(_selectedProduct)) ...[
                const SizedBox(height: 12),
                LossPricingChoice(
                  product: _selectedProduct!,
                  sellAsUnit: _sellAsUnit,
                  onChanged: (v) => setState(() => _sellAsUnit = v),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantityController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Quantité perdue *'),
                validator: (v) {
                  final value = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                  if (value == null || value <= 0) return 'Quantité invalide';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextField(controller: _reasonController, decoration: const InputDecoration(labelText: 'Motif (optionnel)')),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
