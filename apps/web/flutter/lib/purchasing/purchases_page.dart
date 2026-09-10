import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import 'purchase_order_detail_page.dart';
import 'purchasing_models.dart';
import 'purchasing_repository.dart';
import 'suppliers_page.dart';

final _dateFormat = DateFormat('dd/MM/yyyy');

/// Deux types de produits achetables (voir docs/api/purchasing.md), en 3
/// sous-modules : Créer une commande (choix produit + quantité, un produit à
/// la fois) → Liste de commandes (lignes accumulées de la commande en cours,
/// "Créer la commande" l'enregistre) → Historique (commandes déjà
/// enregistrées, avec modification/suppression).
/// - **Par casier** (Bières, Vins, Sucreries) : nbre de casiers commandés,
///   bottlesPerCase/purchasePricePerCase toujours dérivés du Catalogue.
/// - **Prix variable** (Poulets, Poissons, Plats africains) : quantité
///   achetée + prix d'achat unitaire, saisis directement (pas de casier) —
///   met à jour Product.purchasePrice pour que les rapports/graphiques par
///   catégorie fonctionnent pour ces produits.
class PurchasesPage extends StatefulWidget {
  const PurchasesPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage>
    with SingleTickerProviderStateMixin {
  late final PurchasingRepository _repository = PurchasingRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final CatalogRepository _catalog = CatalogRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final TabController _tabController = TabController(
    length: 3,
    vsync: this,
  );

  late Future<void> _future = _load();
  List<Supplier> _suppliers = [];
  List<Product> _caseProducts = [];
  List<Product> _variableProducts = [];
  List<Purchase> _purchases = [];

  // État de la commande en cours (partagé entre "Créer une commande" et "Liste de commandes").
  String? _draftSupplierId;
  DateTime _draftOrderDate = DateTime.now();
  final _orderNumberController = TextEditingController();
  final List<_DraftLine> _draftLines = [];

  // Ligne en cours de configuration dans "Créer une commande".
  Product? _selectedProduct;
  final _casesOrderedController = TextEditingController(text: '1');
  final _quantityOrderedController = TextEditingController(text: '1');
  final _unitPurchasePriceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshOrderNumberSuggestion();
  }

  Future<void> _load() async {
    final products = await _catalog.listProducts();
    final suppliers = await _repository.listSuppliers();
    final purchases = await _repository.listPurchases();
    _caseProducts = products
        .where((p) => p.status == 'active' && p.hasCasePricing)
        .toList();
    _variableProducts = products
        .where((p) => p.status == 'active' && p.hasVariablePricing)
        .toList();
    _suppliers = suppliers;
    _purchases = purchases;
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _refreshOrderNumberSuggestion() async {
    try {
      final next = await _repository.nextOrderNumber(
        supplierId: _draftSupplierId,
      );
      if (!mounted) return;
      setState(() => _orderNumberController.text = '$next');
    } catch (_) {
      // Simple suggestion de convenance — jamais bloquant, l'utilisateur peut toujours saisir manuellement.
    }
  }

  Future<void> _pickProduct() async {
    final chosen = await showDialog<Product>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Choisir un produit'),
        children: [
          if (_caseProducts.isEmpty && _variableProducts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'Aucun produit achetable. Activez "Prix par casier" (Bières, Vins, Sucreries) ou '
                '"Prix variable" (Poulets, Poissons, Plats africains) sur une catégorie dans le Catalogue.',
              ),
            ),
          if (_caseProducts.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: Text(
                'Prix par casier',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            for (final product in _caseProducts)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(product),
                child: Text(product.name),
              ),
          ],
          if (_variableProducts.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: Text(
                'Prix variable',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            for (final product in _variableProducts)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(product),
                child: Text(product.name),
              ),
          ],
        ],
      ),
    );
    if (chosen == null) return;
    setState(() {
      _selectedProduct = chosen;
      _casesOrderedController.text = '1';
      _quantityOrderedController.text = '1';
      _unitPurchasePriceController.clear();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _draftOrderDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Date de la commande',
    );
    if (picked == null) return;
    setState(() => _draftOrderDate = picked);
  }

  void _addLineToOrder() {
    final product = _selectedProduct;
    if (product == null) return;
    if (product.hasVariablePricing) {
      final quantity = double.tryParse(
        _quantityOrderedController.text.trim().replaceAll(',', '.'),
      );
      final unitPrice = double.tryParse(
        _unitPurchasePriceController.text.trim().replaceAll(',', '.'),
      );
      if (quantity == null ||
          quantity <= 0 ||
          unitPrice == null ||
          unitPrice <= 0) {
        return;
      }
      setState(() {
        _draftLines.add(
          _DraftLine.variable(
            product: product,
            quantityOrdered: quantity,
            unitPurchasePrice: unitPrice,
          ),
        );
        _selectedProduct = null;
      });
    } else {
      final cases = double.tryParse(
        _casesOrderedController.text.trim().replaceAll(',', '.'),
      );
      if (cases == null || cases <= 0) return;
      setState(() {
        _draftLines.add(
          _DraftLine.caseOrder(product: product, casesOrdered: cases),
        );
        _selectedProduct = null;
      });
    }
    _tabController.animateTo(1);
  }

  void _removeDraftLine(_DraftLine line) =>
      setState(() => _draftLines.remove(line));

  Future<void> _submitOrder() async {
    if (_draftLines.isEmpty) return;
    final orderNumber = int.tryParse(_orderNumberController.text.trim());
    if (orderNumber == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('N° de commande invalide')));
      return;
    }
    try {
      await _repository.createPurchase(
        supplierId: _draftSupplierId,
        orderNumber: orderNumber,
        orderDate: _draftOrderDate,
        items: _draftLines.map((l) => l.toApiItem()).toList(),
      );
      setState(() {
        _draftLines.clear();
        _draftSupplierId = null;
        _draftOrderDate = DateTime.now();
      });
      _refreshOrderNumberSuggestion();
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Commande enregistrée.')));
      _tabController.animateTo(2);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _orderNumberController.dispose();
    _casesOrderedController.dispose();
    _quantityOrderedController.dispose();
    _unitPurchasePriceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Achats'),
        actions: [
          IconButton(
            tooltip: 'Fournisseurs',
            icon: const Icon(Icons.local_shipping_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SuppliersPage(repository: _repository),
                ),
              );
              _reload();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Créer une commande'),
            Tab(text: 'Liste de commandes'),
            Tab(text: 'Historique'),
          ],
        ),
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
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _reload,
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            );
          }
          return TabBarView(
            controller: _tabController,
            children: [_buildCreateTab(), _buildListTab(), _buildHistoryTab()],
          );
        },
      ),
    );
  }

  Widget _buildCreateTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text('Date : ${_dateFormat.format(_draftOrderDate)}'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _orderNumberController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'N° de la commande'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _draftSupplierId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Fournisseur'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Aucun')),
            for (final supplier in _suppliers)
              DropdownMenuItem(value: supplier.id, child: Text(supplier.name)),
          ],
          onChanged: (value) {
            setState(() => _draftSupplierId = value);
            _refreshOrderNumberSuggestion();
          },
        ),
        const Divider(height: 32),
        if (_selectedProduct == null)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const Text('Aucun produit sélectionné.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickProduct,
                    icon: const Icon(Icons.add),
                    label: const Text('Choisir un produit'),
                  ),
                ],
              ),
            ),
          )
        else
          _selectedProduct!.hasVariablePricing
              ? _buildVariableProductCard()
              : _buildCaseProductCard(),
      ],
    );
  }

  Widget _buildCaseProductCard() {
    final product = _selectedProduct!;
    final cases =
        double.tryParse(
          _casesOrderedController.text.trim().replaceAll(',', '.'),
        ) ??
        0;
    final totalBottles = cases * (product.bottlesPerCase ?? 0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _productHeader(product),
            const SizedBox(height: 12),
            _readOnlyField(
              'Nbre de bouteilles par casier',
              '${product.bottlesPerCase ?? '—'}',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _casesOrderedController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Nbre de casiers commandés',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            _readOnlyField(
              'Nbre total de bouteilles',
              totalBottles.toStringAsFixed(0),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _addLineToOrder,
              child: const Text('Ajouter la commande'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVariableProductCard() {
    final product = _selectedProduct!;
    final quantity =
        double.tryParse(
          _quantityOrderedController.text.trim().replaceAll(',', '.'),
        ) ??
        0;
    final unitPrice =
        double.tryParse(
          _unitPurchasePriceController.text.trim().replaceAll(',', '.'),
        ) ??
        0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _productHeader(product),
            const SizedBox(height: 4),
            const Text(
              'Prix variable : quantité et prix d\'achat unitaire saisis ici, pas de casier fixe.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantityOrderedController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantité achetée'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _unitPurchasePriceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: "Prix d'achat unitaire (FCFA)",
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            _readOnlyField('Total', (quantity * unitPrice).toStringAsFixed(0)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _addLineToOrder,
              child: const Text('Ajouter la commande'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _productHeader(Product product) {
    final primaryImage =
        product.images.where((i) => i.isPrimary).firstOrNull ??
        product.images.firstOrNull;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 64,
            height: 64,
            child: primaryImage == null
                ? const ColoredBox(
                    color: Color(0x11000000),
                    child: Icon(Icons.local_drink_outlined),
                  )
                : FutureBuilder<String>(
                    future: _catalog.getImageUrl(
                      product.id,
                      primaryImage.id,
                      variant: 'thumbnail',
                    ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const ColoredBox(color: Color(0x11000000));
                      }
                      return ColoredBox(
                        color: const Color(0x11000000),
                        child: Image.network(
                          snapshot.data!,
                          fit: BoxFit.contain,
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            product.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ),
        TextButton(onPressed: _pickProduct, child: const Text('Changer')),
      ],
    );
  }

  Widget _buildListTab() {
    final totalPrice = _draftLines.fold<double>(
      0,
      (sum, l) => sum + l.lineTotal,
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: _readOnlyField(
                  'Date',
                  _dateFormat.format(_draftOrderDate),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _readOnlyField(
                  'N° de la commande',
                  _orderNumberController.text,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _draftLines.isEmpty
              ? const Center(
                  child: Text(
                    'Aucune ligne — ajoutez un produit depuis "Créer une commande".',
                  ),
                )
              : ListView(
                  children: [
                    for (final line in _draftLines)
                      ListTile(
                        title: Text(line.product.name),
                        subtitle: Text(line.summary),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _removeDraftLine(line),
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
                    '${totalPrice.toStringAsFixed(0)} FCFA',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _draftLines.isEmpty ? null : _submitOrder,
                child: const Text('Créer la commande'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    if (_purchases.isEmpty) {
      return const Center(child: Text('Aucune commande créée.'));
    }
    return ListView(
      children: [
        for (final purchase in _purchases)
          ListTile(
            title: Text(
              'N° ${purchase.orderNumber} — ${purchase.supplier?.name ?? 'Sans fournisseur'}',
            ),
            subtitle: Text(
              '${_dateFormat.format(purchase.orderDate)} — ${purchase.quantitySummary} — '
              '${purchase.total.toStringAsFixed(0)} FCFA',
            ),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PurchaseOrderDetailPage(
                    repository: _repository,
                    catalog: _catalog,
                    purchase: purchase,
                  ),
                ),
              );
              _reload();
            },
          ),
      ],
    );
  }
}

Widget _readOnlyField(String label, String value) => InputDecorator(
  decoration: InputDecoration(labelText: label),
  child: Text(value),
);

class _DraftLine {
  _DraftLine._({
    required this.product,
    this.casesOrdered,
    this.quantityOrdered,
    this.unitPurchasePrice,
  });

  factory _DraftLine.caseOrder({
    required Product product,
    required double casesOrdered,
  }) => _DraftLine._(product: product, casesOrdered: casesOrdered);

  factory _DraftLine.variable({
    required Product product,
    required double quantityOrdered,
    required double unitPurchasePrice,
  }) => _DraftLine._(
    product: product,
    quantityOrdered: quantityOrdered,
    unitPurchasePrice: unitPurchasePrice,
  );

  final Product product;
  final double? casesOrdered;
  final double? quantityOrdered;
  final double? unitPurchasePrice;

  bool get isCasePricing => casesOrdered != null;
  double get purchasePricePerCase => product.purchasePricePerCase ?? 0;

  double get lineTotal => isCasePricing
      ? casesOrdered! * purchasePricePerCase
      : quantityOrdered! * unitPurchasePrice!;

  String get summary => isCasePricing
      ? '${purchasePricePerCase.toStringAsFixed(0)} FCFA/casier × ${casesOrdered!.toStringAsFixed(0)} casier(s) = ${lineTotal.toStringAsFixed(0)} FCFA'
      : '${unitPurchasePrice!.toStringAsFixed(0)} FCFA/unité × ${quantityOrdered!.toStringAsFixed(0)} = ${lineTotal.toStringAsFixed(0)} FCFA';

  Map<String, dynamic> toApiItem() => isCasePricing
      ? {'productId': product.id, 'casesOrdered': casesOrdered}
      : {
          'productId': product.id,
          'quantityOrdered': quantityOrdered,
          'unitPurchasePrice': unitPurchasePrice,
        };
}
