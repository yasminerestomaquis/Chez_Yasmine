import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../common/formatting.dart';
import 'purchasing_models.dart';
import 'purchasing_repository.dart';

final _dateFormat = DateFormat('dd/MM/yyyy');

/// Détail d'une commande de l'Historique — même présentation que le sous-module
/// Liste de commandes (nom du produit, Prix d'achat par casier, Nbre de
/// casiers commandés, Prix total des casiers), avec modification (remplace
/// l'intégralité des lignes) et suppression.
class PurchaseOrderDetailPage extends StatefulWidget {
  const PurchaseOrderDetailPage({
    super.key,
    required this.repository,
    required this.catalog,
    required this.purchase,
    this.readOnly = false,
  });

  final PurchasingRepository repository;
  final CatalogRepository catalog;
  final Purchase purchase;
  // Masque Modifier/Supprimer et le bouton d'ajout de ligne (rôle Serveur :
  // `purchases.view` sans `purchases.manage`, demande utilisateur du
  // 2026-09-11) — consultation seule des lignes de la commande.
  final bool readOnly;

  @override
  State<PurchaseOrderDetailPage> createState() =>
      _PurchaseOrderDetailPageState();
}

class _PurchaseOrderDetailPageState extends State<PurchaseOrderDetailPage> {
  late Purchase _purchase = widget.purchase;
  bool _isEditing = false;
  bool _isBusy = false;

  List<Product> _caseProducts = [];
  Map<String, Product> _productsById = {};
  List<Supplier> _suppliers = [];
  late List<_EditLine> _editLines;
  late final TextEditingController _orderNumberController;
  late DateTime _orderDate;
  String? _supplierId;

  @override
  void initState() {
    super.initState();
    _orderNumberController = TextEditingController(
      text: '${_purchase.orderNumber}',
    );
    _orderDate = _purchase.orderDate;
    _supplierId = _purchase.supplierId;
    _editLines = _purchase.items.map(_EditLine.fromItem).toList();
    _loadPickerData();
  }

  Future<void> _loadPickerData() async {
    final products = await widget.catalog.listProducts();
    // `listSuppliers` exige `purchases.manage` (choix fournisseur en édition,
    // impossible en lecture seule) — inutile et provoquerait un 403.
    final suppliers = widget.readOnly
        ? <Supplier>[]
        : await widget.repository.listSuppliers();
    if (!mounted) return;
    setState(() {
      _caseProducts = products
          .where((p) => p.status == 'active' && p.hasCasePricing)
          .toList();
      _productsById = {for (final p in products) p.id: p};
      _suppliers = suppliers;
    });
  }

  /// Vignette photo (reprise du Catalogue, même principe que le sous-module
  /// Créer une commande) — repli sur une icône générique si le produit n'a
  /// pas encore été chargé ou n'a pas de photo.
  Widget _thumbnail(String productId) {
    final product = _productsById[productId];
    final primaryImage =
        product?.images.where((i) => i.isPrimary).firstOrNull ??
        product?.images.firstOrNull;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 44,
        child: primaryImage == null
            ? const ColoredBox(
                color: Color(0x11000000),
                child: Icon(Icons.local_drink_outlined, size: 20),
              )
            : FutureBuilder<String>(
                future: widget.catalog.getImageUrl(
                  product!.id,
                  primaryImage.id,
                  variant: 'thumbnail',
                ),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const ColoredBox(color: Color(0x11000000));
                  }
                  return ColoredBox(
                    color: const Color(0x11000000),
                    child: Image.network(snapshot.data!, fit: BoxFit.contain),
                  );
                },
              ),
      ),
    );
  }

  void _startEditing() => setState(() {
    _isEditing = true;
    _orderNumberController.text = '${_purchase.orderNumber}';
    _orderDate = _purchase.orderDate;
    _supplierId = _purchase.supplierId;
    _editLines = _purchase.items.map(_EditLine.fromItem).toList();
  });

  void _cancelEditing() => setState(() => _isEditing = false);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _orderDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Date de la commande',
    );
    if (picked == null) return;
    setState(() => _orderDate = picked);
  }

  Future<void> _addLine() async {
    final chosen = await showDialog<Product>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Choisir un produit'),
        children: [
          for (final product in _caseProducts)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(product),
              child: Text(product.name),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    setState(() => _editLines.add(_EditLine.fromProduct(chosen)));
  }

  Future<void> _save() async {
    if (_editLines.isEmpty) return;
    final orderNumber = int.tryParse(_orderNumberController.text.trim());
    if (orderNumber == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('N° de commande invalide')));
      return;
    }
    setState(() => _isBusy = true);
    try {
      final updated = await widget.repository.updatePurchase(
        _purchase.id,
        supplierId: _supplierId,
        orderNumber: orderNumber,
        orderDate: _orderDate,
        items: _editLines
            .map(
              (l) => {'productId': l.productId, 'casesOrdered': l.casesOrdered},
            )
            .toList(),
      );
      if (!mounted) return;
      setState(() {
        _purchase = updated;
        _isEditing = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Commande modifiée.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette commande ?'),
        content: Text(
          'La commande n°${_purchase.orderNumber} sera supprimée et le stock qu\'elle avait fait entrer sera retiré '
          '(sans jamais passer sous 0, même si une partie a déjà été vendue).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isBusy = true);
    try {
      await widget.repository.deletePurchase(_purchase.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
      setState(() => _isBusy = false);
    }
  }

  @override
  void dispose() {
    _orderNumberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalCases = _isEditing
        ? _editLines.fold<double>(0, (sum, l) => sum + l.casesOrdered)
        : _purchase.items.fold<double>(0, (sum, l) => sum + l.casesOrdered);
    final totalPrice = _isEditing
        ? _editLines.fold<double>(0, (sum, l) => sum + l.lineTotal)
        : _purchase.items.fold<double>(0, (sum, l) => sum + l.lineTotal);

    return Scaffold(
      appBar: AppBar(
        title: Text('Commande n°${_purchase.orderNumber}'),
        actions: widget.readOnly
            ? const []
            : _isEditing
            ? [
                TextButton(
                  onPressed: _isBusy ? null : _cancelEditing,
                  child: const Text(
                    'Annuler',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Modifier',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _isBusy ? null : _startEditing,
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _isBusy ? null : _delete,
                ),
              ],
      ),
      floatingActionButton: _isEditing
          ? FloatingActionButton(
              onPressed: _addLine,
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _isEditing
                ? Column(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text('Date : ${_dateFormat.format(_orderDate)}'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _orderNumberController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'N° de la commande',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _supplierId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Fournisseur',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Aucun'),
                          ),
                          for (final supplier in _suppliers)
                            DropdownMenuItem(
                              value: supplier.id,
                              child: Text(supplier.name),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _supplierId = value),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _field(
                          'Date',
                          _dateFormat.format(_purchase.orderDate),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(
                          'N° de la commande',
                          '${_purchase.orderNumber}',
                        ),
                      ),
                    ],
                  ),
          ),
          Expanded(
            child: _isEditing
                ? ListView(
                    children: [
                      for (final line in _editLines)
                        ListTile(
                          leading: _thumbnail(line.productId),
                          title: Text(line.productName),
                          subtitle: Text(
                            '${formatAmount(line.purchasePricePerCase)} FCFA/casier',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 72,
                                child: TextFormField(
                                  initialValue: line.casesOrdered
                                      .toStringAsFixed(0),
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'Casiers',
                                  ),
                                  onChanged: (v) => setState(
                                    () => line.casesOrdered =
                                        double.tryParse(v) ?? line.casesOrdered,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () =>
                                    setState(() => _editLines.remove(line)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                : ListView(
                    children: [
                      for (final line in _purchase.items)
                        ListTile(
                          leading: _thumbnail(line.productId),
                          title: Text(line.productName),
                          subtitle: Text(
                            '${formatAmount(line.purchasePricePerCase)} FCFA/casier × '
                            '${line.casesOrdered.toStringAsFixed(0)} casier(s)',
                          ),
                          trailing: Text(
                            '${formatAmount(line.lineTotal)} FCFA',
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
                    const Text(
                      'Total',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      '${totalCases.toStringAsFixed(0)} casier(s)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${formatAmount(totalPrice)} FCFA',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (_isEditing) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _isBusy || _editLines.isEmpty ? null : _save,
                    child: _isBusy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Enregistrer les modifications'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, String value) => InputDecorator(
    decoration: InputDecoration(labelText: label),
    child: Text(value),
  );
}

class _EditLine {
  _EditLine({
    required this.productId,
    required this.productName,
    required this.bottlesPerCase,
    required this.purchasePricePerCase,
    required this.casesOrdered,
  });

  final String productId;
  final String productName;
  final int bottlesPerCase;
  final double purchasePricePerCase;
  double casesOrdered;

  double get lineTotal => casesOrdered * purchasePricePerCase;

  factory _EditLine.fromItem(PurchaseItem item) => _EditLine(
    productId: item.productId,
    productName: item.productName,
    bottlesPerCase: item.bottlesPerCase,
    purchasePricePerCase: item.purchasePricePerCase,
    casesOrdered: item.casesOrdered,
  );

  factory _EditLine.fromProduct(Product product) => _EditLine(
    productId: product.id,
    productName: product.name,
    bottlesPerCase: product.bottlesPerCase ?? 0,
    purchasePricePerCase: product.purchasePricePerCase ?? 0,
    casesOrdered: 1,
  );
}
