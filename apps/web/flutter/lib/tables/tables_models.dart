class RestaurantTable {
  RestaurantTable({required this.id, required this.name, this.zone, required this.status});

  final String id;
  final String name;
  final String? zone;
  final String status;

  factory RestaurantTable.fromJson(Map<String, dynamic> json) => RestaurantTable(
        id: json['id'] as String,
        name: json['name'] as String,
        zone: json['zone'] as String?,
        status: json['status'] as String,
      );
}

class OrderItemDetail {
  OrderItemDetail({required this.id, required this.productId, required this.productName, required this.quantity, required this.unitPrice});

  final String id;
  final String productId;
  final String productName;
  final double quantity;
  final double unitPrice;

  factory OrderItemDetail.fromJson(Map<String, dynamic> json) => OrderItemDetail(
        id: json['id'] as String,
        productId: json['productId'] as String,
        productName: (json['product'] as Map<String, dynamic>?)?['name'] as String? ?? '',
        quantity: (json['quantity'] as num).toDouble(),
        unitPrice: (json['unitPrice'] as num).toDouble(),
      );
}

class OrderDetail {
  OrderDetail({required this.id, required this.tableId, required this.status, required this.items});

  final String id;
  final String? tableId;
  final String status;
  final List<OrderItemDetail> items;

  double get total => items.fold(0, (sum, item) => sum + item.quantity * item.unitPrice);

  factory OrderDetail.fromJson(Map<String, dynamic> json) => OrderDetail(
        id: json['id'] as String,
        tableId: json['tableId'] as String?,
        status: json['status'] as String,
        items: (json['items'] as List<dynamic>).map((e) => OrderItemDetail.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
