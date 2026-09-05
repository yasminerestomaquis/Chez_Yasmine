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

class PurchaseItem {
  PurchaseItem({required this.productId, required this.quantity, required this.unitPrice});

  final String productId;
  final double quantity;
  final double unitPrice;

  factory PurchaseItem.fromJson(Map<String, dynamic> json) => PurchaseItem(
        productId: json['productId'] as String,
        quantity: (json['quantity'] as num).toDouble(),
        unitPrice: (json['unitPrice'] as num).toDouble(),
      );
}

const purchaseStatusLabels = {'pending': 'En attente', 'received': 'Reçu', 'cancelled': 'Annulé'};

class Purchase {
  Purchase({required this.id, required this.status, required this.total, this.supplier, required this.items});

  final String id;
  final String status;
  final double total;
  final Supplier? supplier;
  final List<PurchaseItem> items;

  factory Purchase.fromJson(Map<String, dynamic> json) => Purchase(
        id: json['id'] as String,
        status: json['status'] as String,
        total: (json['total'] as num).toDouble(),
        supplier: json['supplier'] != null ? Supplier.fromJson(json['supplier'] as Map<String, dynamic>) : null,
        items: (json['items'] as List<dynamic>).map((e) => PurchaseItem.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
