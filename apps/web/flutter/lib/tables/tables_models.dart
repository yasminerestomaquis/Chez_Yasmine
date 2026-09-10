class ReservationInfo {
  ReservationInfo({
    required this.id,
    this.customerName,
    this.phone,
    required this.reservedAt,
  });

  final String id;
  final String? customerName;
  final String? phone;
  final DateTime reservedAt;

  factory ReservationInfo.fromJson(Map<String, dynamic> json) =>
      ReservationInfo(
        id: json['id'] as String,
        customerName: json['customerName'] as String?,
        phone: json['phone'] as String?,
        reservedAt: DateTime.parse(json['reservedAt'] as String),
      );
}

class RestaurantTable {
  RestaurantTable({
    required this.id,
    required this.name,
    this.zone,
    required this.status,
    this.guestCount,
    this.currentTotal,
    this.reservation,
  });

  final String id;
  final String name;
  final String? zone;
  final String status;

  /// Nombre de convives de la commande ouverte, le cas échéant (saisi à
  /// l'ouverture de la table — voir `TablesRepository.openTable`).
  final int? guestCount;

  /// Total de la commande ouverte, le cas échéant.
  final double? currentTotal;

  /// Réservation active (statut 'pending'), le cas échéant.
  final ReservationInfo? reservation;

  factory RestaurantTable.fromJson(Map<String, dynamic> json) =>
      RestaurantTable(
        id: json['id'] as String,
        name: json['name'] as String,
        zone: json['zone'] as String?,
        status: json['status'] as String,
        guestCount: json['guestCount'] as int?,
        currentTotal: (json['currentTotal'] as num?)?.toDouble(),
        reservation: json['reservation'] != null
            ? ReservationInfo.fromJson(
                json['reservation'] as Map<String, dynamic>,
              )
            : null,
      );
}

class OrderItemDetail {
  OrderItemDetail({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
  });

  final String id;
  final String productId;
  final String productName;
  final double quantity;
  final double unitPrice;

  factory OrderItemDetail.fromJson(Map<String, dynamic> json) =>
      OrderItemDetail(
        id: json['id'] as String,
        productId: json['productId'] as String,
        productName:
            (json['product'] as Map<String, dynamic>?)?['name'] as String? ??
            '',
        quantity: (json['quantity'] as num).toDouble(),
        unitPrice: (json['unitPrice'] as num).toDouble(),
      );
}

class OrderDetail {
  OrderDetail({
    required this.id,
    required this.tableId,
    required this.status,
    required this.items,
  });

  final String id;
  final String? tableId;
  final String status;
  final List<OrderItemDetail> items;

  double get total =>
      items.fold(0, (sum, item) => sum + item.quantity * item.unitPrice);

  factory OrderDetail.fromJson(Map<String, dynamic> json) => OrderDetail(
    id: json['id'] as String,
    tableId: json['tableId'] as String?,
    status: json['status'] as String,
    items: (json['items'] as List<dynamic>)
        .map((e) => OrderItemDetail.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
