import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/models.dart';
import '../common/formatting.dart';
import '../sync/device_id.dart';
import '../sync/pending_operation.dart';
import '../sync/sync_queue_service.dart';
import 'purchase_order_detail_page.dart';
import 'purchasing_models.dart';
import 'purchasing_repository.dart';
import 'suppliers_page.dart';

final _dateFormat = DateFormat('dd/MM/yyyy');

/// Commande par casier (Bières, Vins, Sucreries — voir docs/api/purchasing.md),
/// en 3 sous-modules : Créer une commande (choix produit + casiers commandés,
/// un produit à la fois) → Liste de commandes (lignes accumulées de la
/// commande en cours, "Créer la commande" l'enregistre) → Historique
/// (commandes déjà enregistrées, avec modification/suppression).
class PurchasesPage extends StatefulWidget {
  const PurchasesPage({
    super.key,
    required this.establishmentId,
    required this.roleName,
  });

  final String establishmentId;
  final String roleName;

  @override
  State<PurchasesPage> createState() => _PurchasesPageState();
}

class _PurchasesPageState extends State<PurchasesPage>
    with SingleTickerProviderStateMixin {
  // Comparaison par nom de rôle — même limitation/raison que
  // HomeDashboard._isServeur. Demande utilisateur du 2026-09-11 : le Serveur
  // a `purchases.view` (lecture) mais pas `purchases.manage` — accès en
  // lecture seule à l'onglet Historique uniquement, ni "Créer une commande"
  // ni "Liste de commandes" ni gestion des fournisseurs.
  bool get _isServeur => widget.roleName == 'Serveur';

  late final PurchasingRepository _repository = PurchasingRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final CatalogRepository _catalog = CatalogRepository(
    ApiClient(),
    widget.establishmentId,
  );
  late final SyncQueueService _syncQueue = SyncQueueService(
    ApiClient(),
    widget.establishmentId,
  );
  late final TabController _tabController = TabController(
    length: _isServeur ? 1 : 3,
    vsync: this,
  );

  late Future<void> _future = _load();
  List<Supplier> _suppliers = [];
  // Produits commandables : prix par casier (Bières, Vins, Sucreries) OU
  // prix de référence variable commandé au litre (ex. Gbêlê — décision
  // utilisateur du 2026-09-24, voir `Product.isReferencePriced`).
  List<Product> _orderableProducts = [];
  List<Purchase> _purchases = [];

  // État de la commande en cours (partagé entre "Créer une commande" et "Liste de commandes").
  String? _draftSupplierId;
  DateTime _draftOrderDate = DateTime.now();
  final _orderNumberController = TextEditingController();
  final List<_DraftLine> _draftLines = [];

  // Ligne en cours de configuration dans "Créer une commande".
  Product? _selectedProduct;
  final _casesOrderedController = TextEditingController(text: '1');
  // Litres commandés pour un produit à prix de référence variable (ex.
  // Gbêlê) — saisie libre plutôt que figée à 25/50 L, décision utilisateur
  // du 2026-09-25 (25 L par défaut).
  final _litersOrderedController = TextEditingController(text: '25');

  @override
  void initState() {
    super.initState();
    // `nextOrderNumber` exige `purchases.manage` (suggestion pour "Créer une
    // commande", onglet absent en lecture seule) — l'appeler pour un Serveur
    // ne ferait que produire un 403 ignoré silencieusement.
    if (!_isServeur) _refreshOrderNumberSuggestion();
  }

  Future<void> _load() async {
    final products = await _catalog.listProducts();
    // `listSuppliers` exige `purchases.manage` (choix fournisseur en
    // création/édition, indisponibles en lecture seule) — inutile et
    // provoquerait un 403 pour un Serveur, dont l'onglet Historique affiche
    // le fournisseur déjà inclus dans chaque `Purchase` (`listPurchases`).
    final suppliers = _isServeur
        ? <Supplier>[]
        : await _repository.listSuppliers();
    final purchases = await _repository.listPurchases();
    _orderableProducts = products
        .where((p) => p.status == 'active' && (p.hasCasePricing || p.isReferencePriced))
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
          if (_orderableProducts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'Aucun produit commandable. Activez "Prix par casier" sur une catégorie '
                '(ex. Bières, Vins, Sucreries) dans le Catalogue, ou "Prix de vente saisi à la '
                'vente" avec un prix de référence (ex. Gbêlê).',
              ),
            ),
          for (final product in _orderableProducts)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(product),
              child: Text(product.name),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    setState(() {
      _selectedProduct = chosen;
      _casesOrderedController.text = '1';
      _litersOrderedController.text = '25';
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
    if (product.isReferencePriced) {
      final liters = double.tryParse(_litersOrderedController.text.trim().replaceAll(',', '.'));
      if (liters == null || liters <= 0) return;
      setState(() {
        _draftLines.add(_DraftLine(product: product, casesOrdered: liters, isLiters: true));
        _selectedProduct = null;
        _litersOrderedController.text = '25';
      });
      _tabController.animateTo(1);
      return;
    }
    final cases = double.tryParse(
      _casesOrderedController.text.trim().replaceAll(',', '.'),
    );
    if (cases == null || cases <= 0) return;
    setState(() {
      _draftLines.add(_DraftLine(product: product, casesOrdered: cases));
      _selectedProduct = null;
      _casesOrderedController.text = '1';
    });
    _tabController.animateTo(1);
  }

  void _removeDraftLine(_DraftLine line) =>
      setState(() => _draftLines.remove(line));

  Future<void> _submitOrder({bool pending = false}) async {
    if (_draftLines.isEmpty) return;
    final orderNumber = int.tryParse(_orderNumberController.text.trim());
    if (orderNumber == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('N° de commande invalide')));
      return;
    }
    final purchaseId = const Uuid().v4();
    final items = _draftLines
        .map(
          (l) => {
            'productId': l.product.id,
            if (l.isLiters) 'litersOrdered': l.casesOrdered.toInt() else 'casesOrdered': l.casesOrdered,
          },
        )
        .toList();
    try {
      await _repository.createPurchase(
        id: purchaseId,
        supplierId: _draftSupplierId,
        orderNumber: orderNumber,
        orderDate: _draftOrderDate,
        items: items,
        pending: pending,
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
          .showSnackBar(SnackBar(content: Text(pending ? 'Commande mise en attente (aucune entrée de stock).' : 'Commande enregistrée.')));
      _tabController.animateTo(2);
    } on ApiException catch (e) {
      // Rejet métier réel (ex. produit non conforme au module par casier) —
      // rejouer ne changerait rien, jamais mis en file.
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      // Aucune réponse HTTP reçue — coupure réseau : mise en file (voir
      // PosPage._checkout pour le même principe), rejouée via SyncService
      // (`entityType: 'purchase'`) au retour du réseau.
      await _syncQueue.enqueue(
        PendingOperation(
          id: purchaseId,
          entityType: 'purchase',
          deviceId: await getDeviceId(),
          payload: {
            'supplierId': ?_draftSupplierId,
            'orderNumber': orderNumber,
            'orderDate': _draftOrderDate.toIso8601String(),
            'items': items,
            if (pending) 'status': 'pending',
          },
          createdAt: DateTime.now(),
        ),
      );
      setState(() {
        _draftLines.clear();
        _draftSupplierId = null;
        _draftOrderDate = DateTime.now();
      });
      _refreshOrderNumberSuggestion();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hors ligne : commande enregistrée localement, elle sera synchronisée automatiquement.',
          ),
        ),
      );
      _tabController.animateTo(2);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _orderNumberController.dispose();
    _casesOrderedController.dispose();
    _litersOrderedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Achats'),
        actions: [
          // Fournisseurs : gestion (création/édition), hors de portée d'un
          // accès en lecture seule.
          if (!_isServeur)
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
        // Un seul onglet en lecture seule (Historique) : pas de TabBar à
        // afficher, elle n'aurait rien à faire sélectionner.
        bottom: _isServeur
            ? null
            : TabBar(
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
          if (_isServeur) return _buildHistoryTab();
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
          _buildSelectedProductCard(),
      ],
    );
  }

  /// Vignette photo (reprise du Catalogue) — repli sur une icône générique
  /// si le produit n'a pas de photo. Partagée par la carte de sélection et
  /// les lignes de la commande en cours.
  Widget _thumbnail(Product product, {double size = 64}) {
    final primaryImage =
        product.images.where((i) => i.isPrimary).firstOrNull ??
        product.images.firstOrNull;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: primaryImage == null
            ? ColoredBox(
                color: const Color(0x11000000),
                child: Icon(Icons.local_drink_outlined, size: size * 0.4),
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
                    child: Image.network(snapshot.data!, fit: BoxFit.contain),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildSelectedProductCard() {
    final product = _selectedProduct!;
    if (product.isReferencePriced) return _buildSelectedReferencePricedCard(product);
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
            Row(
              children: [
                _thumbnail(product),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _pickProduct,
                  child: const Text('Changer'),
                ),
              ],
            ),
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

  /// Produit à prix de référence variable (ex. Gbêlê) : commandé au litre, au
  /// prix d'achat par litre du Catalogue — pas de "casiers", pas de
  /// bouteilles (décision utilisateur du 2026-09-24, saisie libre du nombre
  /// de litres depuis le 2026-09-25 — plus figée à 25/50 L).
  Widget _buildSelectedReferencePricedCard(Product product) {
    final purchasePrice = product.purchasePrice ?? 0;
    final liters = double.tryParse(_litersOrderedController.text.trim().replaceAll(',', '.')) ?? 0;
    final total = liters * purchasePrice;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _thumbnail(product),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
                TextButton(onPressed: _pickProduct, child: const Text('Changer')),
              ],
            ),
            const SizedBox(height: 12),
            _readOnlyField("Prix d'achat par litre", '${formatAmount(purchasePrice)} FCFA'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _litersOrderedController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Litres commandés *'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            _readOnlyField('Total', '${formatAmount(total)} FCFA'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: purchasePrice > 0 && liters > 0 ? _addLineToOrder : null,
              child: const Text('Ajouter la commande'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListTab() {
    // Casiers et litres additionnés séparément — les mélanger dans un seul
    // total n'aurait pas de sens (une commande peut contenir à la fois des
    // Bières au casier et du Gbêlê au litre, décision utilisateur du
    // 2026-09-24).
    final totalCases = _draftLines
        .where((l) => !l.isLiters)
        .fold<double>(0, (sum, l) => sum + l.casesOrdered);
    final totalLiters = _draftLines
        .where((l) => l.isLiters)
        .fold<double>(0, (sum, l) => sum + l.casesOrdered);
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
                        leading: _thumbnail(line.product, size: 44),
                        title: Text(line.product.name),
                        subtitle: Text(
                          line.isLiters
                              ? '${formatAmount(line.purchasePricePerCase)} FCFA/L × '
                                    '${line.casesOrdered.toStringAsFixed(0)} L = ${formatAmount(line.lineTotal)} FCFA'
                              : '${formatAmount(line.purchasePricePerCase)} FCFA/casier × '
                                    '${line.casesOrdered.toStringAsFixed(0)} casier(s) = ${formatAmount(line.lineTotal)} FCFA',
                        ),
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
                  if (totalCases > 0)
                    Text(
                      '${totalCases.toStringAsFixed(0)} casier(s)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  if (totalCases > 0 && totalLiters > 0) const SizedBox(width: 8),
                  if (totalLiters > 0)
                    Text(
                      '${totalLiters.toStringAsFixed(0)} L',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  const SizedBox(width: 16),
                  Text(
                    '${formatAmount(totalPrice)} FCFA',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _draftLines.isEmpty ? null : () => _submitOrder(pending: true),
                      child: const Text('En attente'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _draftLines.isEmpty ? null : () => _submitOrder(),
                      child: const Text('Créer la commande'),
                    ),
                  ),
                ],
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
            leading: Icon(
              purchase.isPending ? Icons.hourglass_top_rounded : Icons.check_circle_outline,
              color: purchase.isPending ? Colors.orange : Colors.green,
            ),
            trailing: _statusChip(purchase),
            title: Text(
              'N° ${purchase.orderNumber} — ${purchase.supplier?.name ?? 'Sans fournisseur'}',
            ),
            subtitle: Text(
              '${_dateFormat.format(purchase.orderDate)} — ${purchaseQuantitySummary(purchase)} — '
              '${formatAmount(purchase.total)} FCFA',
            ),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PurchaseOrderDetailPage(
                    repository: _repository,
                    catalog: _catalog,
                    purchase: purchase,
                    readOnly: _isServeur,
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

/// Pastille de statut de l'Historique : « Validée » (stock entré) ou « En attente » (projection, sans stock).
Widget _statusChip(Purchase purchase) {
  final label = purchase.isPending ? 'En attente' : (purchase.status == 'received' ? 'Validée' : purchaseStatusLabels[purchase.status] ?? purchase.status);
  final color = purchase.isPending ? Colors.orange : (purchase.status == 'received' ? Colors.green : Colors.grey);
  return Chip(
    label: Text(label, style: TextStyle(color: color.shade800, fontSize: 12)),
    backgroundColor: color.withValues(alpha: 0.12),
    side: BorderSide.none,
    visualDensity: VisualDensity.compact,
  );
}

Widget _readOnlyField(String label, String value) => InputDecorator(
  decoration: InputDecoration(labelText: label),
  child: Text(value),
);

class _DraftLine {
  _DraftLine({required this.product, required this.casesOrdered, this.isLiters = false});

  final Product product;
  // Litres commandés quand [isLiters] est vrai (ex. Gbêlê, 25 ou 50 L) —
  // même champ que le nombre de casiers, pour ne pas dupliquer toute la
  // logique de total/soumission (décision utilisateur du 2026-09-24).
  final double casesOrdered;
  final bool isLiters;

  double get purchasePricePerCase => isLiters ? (product.purchasePrice ?? 0) : (product.purchasePricePerCase ?? 0);
  double get lineTotal => casesOrdered * purchasePricePerCase;
}
