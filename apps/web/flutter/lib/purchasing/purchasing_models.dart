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
      PurchaseItemImage(id: json['id'] as String, isPrimary: json['isPrimary'] as bool);
}

/// Commande par casier (Bières, Vins, Sucreries — voir docs/api/purchasing.md).
/// `quantity`/`unitPrice` restent la vérité stock/comptable (bouteilles,
/// prix par bouteille) ; `casesOrdered`/`bottlesPerCase`/`purchasePricePerCase`
/// sont ce que l'utilisateur a réellement saisi/vu, figé au moment de la
/// commande — c'est ce que l'UI affiche.
class PurchaseItem {
  PurchaseItem({
    required this.productId,
    required this.productName,
    required this.casesOrdered,
    required this.bottlesPerCase,
    required this.purchasePricePerCase,
    this.images = const [],
  });

  final String productId;
  final String productName;
  final double casesOrdered;
  final int bottlesPerCase;
  final double purchasePricePerCase;
  final List<PurchaseItemImage> images;

  double get totalBottles => casesOrdered * bottlesPerCase;
  double get lineTotal => casesOrdered * purchasePricePerCase;

  factory PurchaseItem.fromJson(Map<String, dynamic> json) => PurchaseItem(
        productId: json['productId'] as String,
        productName: (json['product'] as Map<String, dynamic>?)?['name'] as String? ?? '',
        casesOrdered: (json['casesOrdered'] as num).toDouble(),
        bottlesPerCase: (json['bottlesPerCase'] as num).toInt(),
        purchasePricePerCase: (json['purchasePricePerCase'] as num).toDouble(),
        images: ((json['product'] as Map<String, dynamic>?)?['images'] as List<dynamic>? ?? [])
            .map((e) => PurchaseItemImage.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

const purchaseStatusLabels = {'pending': 'En attente', 'received': 'Reçu', 'cancelled': 'Annulé'};

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

  double get totalCases => items.fold(0, (sum, i) => sum + i.casesOrdered);

  factory Purchase.fromJson(Map<String, dynamic> json) => Purchase(
        id: json['id'] as String,
        orderNumber: (json['orderNumber'] as num).toInt(),
        orderDate: DateTime.parse(json['orderDate'] as String),
        status: json['status'] as String,
        total: (json['total'] as num).toDouble(),
        supplierId: json['supplierId'] as String?,
        supplier: json['supplier'] != null ? Supplier.fromJson(json['supplier'] as Map<String, dynamic>) : null,
        items: (json['items'] as List<dynamic>).map((e) => PurchaseItem.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
