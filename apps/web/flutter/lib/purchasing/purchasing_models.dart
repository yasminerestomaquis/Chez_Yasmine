class Supplier {
  Supplier({required this.id, required this.name, this.phone, this.address});

  final String id;
  final String name;
  final String? phone;
  final String? address;

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
    id: json['id'] as String,
    name: json['name'] as String,
    phone: json['phone'] as String?,
    address: json['address'] as String?,
  );
}

class PurchaseItemImage {
  PurchaseItemImage({required this.id, required this.isPrimary});

  final String id;
  final bool isPrimary;

  factory PurchaseItemImage.fromJson(Map<String, dynamic> json) =>
      PurchaseItemImage(
        id: json['id'] as String,
        isPrimary: json['isPrimary'] as bool,
      );
}

/// Une ligne de commande, de l'un des deux types pris en charge par Achats
/// (voir docs/api/purchasing.md) :
/// - **Par casier** (Bières, Vins, Sucreries) : `casesOrdered`/`bottlesPerCase`/
///   `purchasePricePerCase` non nuls — ce que l'utilisateur a saisi/vu, figé
///   au moment de la commande.
/// - **Prix variable** (Poulets, Poissons, Plats africains) : ces trois
///   champs sont nuls ; seuls `quantity` (quantité achetée) et `unitPrice`
///   (prix d'achat unitaire) comptent.
/// `quantity`/`unitPrice` restent dans tous les cas la vérité stock/comptable
/// (`quantity` = ce qui entre en stock, `quantity × unitPrice` = le total de
/// la ligne) — jamais besoin de brancher sur le type pour calculer un total.
class PurchaseItem {
  PurchaseItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.casesOrdered,
    this.bottlesPerCase,
    this.purchasePricePerCase,
    this.images = const [],
  });

  final String productId;
  final String productName;
  final double quantity;
  final double unitPrice;
  final double? casesOrdered;
  final int? bottlesPerCase;
  final double? purchasePricePerCase;
  final List<PurchaseItemImage> images;

  bool get isCasePricing => casesOrdered != null;
  double get lineTotal => quantity * unitPrice;

  factory PurchaseItem.fromJson(Map<String, dynamic> json) => PurchaseItem(
    productId: json['productId'] as String,
    productName:
        (json['product'] as Map<String, dynamic>?)?['name'] as String? ?? '',
    quantity: (json['quantity'] as num).toDouble(),
    unitPrice: (json['unitPrice'] as num).toDouble(),
    casesOrdered: (json['casesOrdered'] as num?)?.toDouble(),
    bottlesPerCase: (json['bottlesPerCase'] as num?)?.toInt(),
    purchasePricePerCase: (json['purchasePricePerCase'] as num?)?.toDouble(),
    images:
        ((json['product'] as Map<String, dynamic>?)?['images']
                    as List<dynamic>? ??
                [])
            .map((e) => PurchaseItemImage.fromJson(e as Map<String, dynamic>))
            .toList(),
  );
}

const purchaseStatusLabels = {
  'pending': 'En attente',
  'received': 'Reçu',
  'cancelled': 'Annulé',
};

class Purchase {
  Purchase({
    required this.id,
    required this.orderNumber,
    required this.orderDate,
    required this.status,
    required this.total,
    this.supplierId,
    this.supplier,
    required this.items,
  });

  final String id;
  final int orderNumber;
  final DateTime orderDate;
  final String status;
  final double total;
  final String? supplierId;
  final Supplier? supplier;
  final List<PurchaseItem> items;

  double get totalCases => items
      .where((i) => i.isCasePricing)
      .fold(0, (sum, i) => sum + i.casesOrdered!);
  double get totalUnits => items
      .where((i) => !i.isCasePricing)
      .fold(0, (sum, i) => sum + i.quantity);

  /// Résumé lisible des quantités commandées, quel que soit le mélange de
  /// types de lignes dans la commande (ex. "2 casier(s) + 20 unité(s)").
  String get quantitySummary {
    final parts = <String>[
      if (totalCases > 0) '${totalCases.toStringAsFixed(0)} casier(s)',
      if (totalUnits > 0) '${totalUnits.toStringAsFixed(0)} unité(s)',
    ];
    return parts.isEmpty ? '0' : parts.join(' + ');
  }

  factory Purchase.fromJson(Map<String, dynamic> json) => Purchase(
    id: json['id'] as String,
    orderNumber: (json['orderNumber'] as num).toInt(),
    orderDate: DateTime.parse(json['orderDate'] as String),
    status: json['status'] as String,
    total: (json['total'] as num).toDouble(),
    supplierId: json['supplierId'] as String?,
    supplier: json['supplier'] != null
        ? Supplier.fromJson(json['supplier'] as Map<String, dynamic>)
        : null,
    items: (json['items'] as List<dynamic>)
        .map((e) => PurchaseItem.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
