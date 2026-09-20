import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../common/order_number_field.dart';
import '../sync/device_id.dart';
import '../sync/pending_operation.dart';
import '../sync/sync_queue_service.dart';
import 'loss_pricing_choice.dart';
import 'losses_repository.dart';

/// Retourne `true` si une perte a été enregistrée (pour rafraîchir l'écran appelant).
Future<bool?> showRecordLossDialog(
  BuildContext context, {
  required LossesRepository repository,
  required CatalogRepository catalogRepository,
  bool allowDateEntry = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _RecordLossDialog(
      repository: repository,
      catalogRepository: catalogRepository,
      allowDateEntry: allowDateEntry,
    ),
  );
}

class _RecordLossDialog extends StatefulWidget {
  const _RecordLossDialog({required this.repository, required this.catalogRepository, required this.allowDateEntry});

  final LossesRepository repository;
  final CatalogRepository catalogRepository;

  /// Champ Date de la perte, réservé aux porteurs de `losses.edit` (Super
  /// Administrateur/Gérant/Serveur, demande utilisateur du 2026-09-20) — le
  /// serveur refuse une date envoyée par un autre rôle.
  final bool allowDateEntry;

  @override
  State<_RecordLossDialog> createState() => _RecordLossDialogState();
}

class _RecordLossDialogState extends State<_RecordLossDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  late final Future<List<Product>> _products = widget.catalogRepository.listProducts();
  Product? _selectedProduct;
  DateTime _date = DateTime.now();
  bool _sellAsUnit = false;
  int? _orderNumber;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  /// Date envoyée : seulement si le champ est proposé et différent d'aujourd'hui
  /// (sinon horodatage serveur, comportement inchangé).
  DateTime? get _sentDate => widget.allowDateEntry && !_isToday ? _date : null;

  bool get _isToday {
    final now = DateTime.now();
    return _date.year == now.year && _date.month == now.month && _date.day == now.day;
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
    // Heure courante conservée : seule la date change.
    final now = DateTime.now();
    setState(() => _date = DateTime(picked.year, picked.month, picked.day, now.hour, now.minute, now.second));
  }

  bool get _sendSellAsUnit => _sellAsUnit && hasLotAndUnitPricing(_selectedProduct);

  Future<void> _submit() async {
    if (_selectedProduct == null) {
      setState(() => _error = 'Choisissez un produit');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final quantity = double.parse(_quantityController.text.trim().replaceAll(',', '.'));
    final reason = _reasonController.text.trim();
    final lossId = const Uuid().v4();

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.repository.recordLoss(
        id: lossId,
        productId: _selectedProduct!.id,
        quantity: quantity,
        reason: reason,
        createdAt: _sentDate,
        sellAsUnit: _sendSellAsUnit,
        orderNumber: _orderNumber,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      // Rejet métier réel — rejouer ne changerait rien, jamais mis en file.
      setState(() => _error = e.message);
    } catch (_) {
      // Aucune réponse HTTP reçue — coupure réseau : mise en file, rejouée
      // via SyncService (`entityType: 'loss'`) au retour du réseau.
      final syncQueue = SyncQueueService(ApiClient(), widget.repository.establishmentId);
      await syncQueue.enqueue(
        PendingOperation(
          id: lossId,
          entityType: 'loss',
          deviceId: await getDeviceId(),
          payload: {
            'productId': _selectedProduct!.id,
            'quantity': quantity,
            'reason': ?(reason.isEmpty ? null : reason),
            'createdAt': ?_sentDate?.toUtc().toIso8601String(),
            if (_sendSellAsUnit) 'sellAsUnit': true,
            'orderNumber': ?_orderNumber,
          },
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hors ligne : perte enregistrée localement, elle sera synchronisée automatiquement.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enregistrer une perte'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.allowDateEntry) ...[
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text('Date : ${DateFormat('dd/MM/yyyy').format(_date)}'),
              ),
              const SizedBox(height: 12),
            ],
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
                return DropdownButtonFormField<Product>(
                  initialValue: _selectedProduct,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Produit *'),
                  items: products.map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(),
                  onChanged: (value) => setState(() {
                    _selectedProduct = value;
                    _sellAsUnit = false;
                    _error = null;
                  }),
                );
              },
            ),
            OrderNumberField(
              productId: _selectedProduct?.id,
              loader: widget.repository.orderNumbers,
              onChanged: (v) => _orderNumber = v,
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
        )),
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
