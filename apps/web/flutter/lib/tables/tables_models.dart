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
    this.openOrderCount = 0,
    this.reservation,
  });

  final String id;
  final String name;
  final String? zone;
  final String status;

  /// Nombre de convives de l'addition ouverte la plus ancienne, le cas
  /// échéant (saisi à l'ouverture de la table — voir `TablesRepository.openTable`).
  final int? guestCount;

  /// Somme des totaux de toutes les additions ouvertes, le cas échéant.
  final double? currentTotal;

  /// Nombre d'additions ouvertes sur cette table — si > 1, l'UI affiche
  /// "N additions" plutôt que le total agrégé (ambigu sinon).
  final int openOrderCount;

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
        openOrderCount: json['openOrderCount'] as int? ?? 0,
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
    this.hasCasePricing = false,
    this.hasVariablePricing = false,
    this.sellAsUnit = false,
    this.referenceSalePrice,
  });

  final String id;
  final String productId;
  final String productName;
  final double quantity;
  final double unitPrice;

  /// Recopiés de la catégorie du produit (`product.category`) : déterminent
  /// l'affichage des champs N° de la commande / N° de marché à
  /// l'encaissement, exactement comme en Caisse (voir `pos_page.dart`).
  final bool hasCasePricing;
  final bool hasVariablePricing;

  /// Recopié de `product.referenceSalePrice` (ex. Gbêlê) : non nul si cette
  /// ligne vient d'un produit à prix de référence variable, où `quantity` est
  /// une fraction (litres) déduite d'un montant payé plutôt qu'un compte
  /// d'unités — voir `TableOrderPage._changeQuantity`, qui traite ces lignes
  /// différemment du +/- générique.
  final double? referenceSalePrice;

  /// Vendu à l'unité plutôt qu'au tarif normal (`unitPrice` reflète déjà le
  /// bon prix) — voir `OrdersService.addItem`. Nécessaire pour que le
  /// checkout applique la même tarification à la vente finale.
  final bool sellAsUnit;

  /// Forme lue par [OrderItemDetail.fromJson] — sert à garder en copie locale
  /// les lignes saisies hors ligne (voir `OfflineOrders`).
  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'sellAsUnit': sellAsUnit,
        'product': {
          'name': productName,
          'referenceSalePrice': referenceSalePrice,
          'category': {'hasCasePricing': hasCasePricing, 'hasVariablePricing': hasVariablePricing},
        },
      };

  factory OrderItemDetail.fromJson(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    final category = product?['category'] as Map<String, dynamic>?;
    return OrderItemDetail(
      id: json['id'] as String,
      productId: json['productId'] as String,
      productName: product?['name'] as String? ?? '',
      quantity: (json['quantity'] as num).toDouble(),
      unitPrice: (json['unitPrice'] as num).toDouble(),
      hasCasePricing: category?['hasCasePricing'] as bool? ?? false,
      hasVariablePricing: category?['hasVariablePricing'] as bool? ?? false,
      sellAsUnit: json['sellAsUnit'] as bool? ?? false,
      referenceSalePrice: (product?['referenceSalePrice'] as num?)?.toDouble(),
    );
  }
}

class OrderDetail {
  OrderDetail({
    required this.id,
    required this.tableId,
    required this.status,
    required this.items,
    this.pendingSync = false,
  });

  final String id;
  final String? tableId;
  final String status;
  final List<OrderItemDetail> items;

  /// Vrai quand cette addition porte des modifications saisies hors ligne pas
  /// encore synchronisées (ou n'existe que sur l'appareil) : toute nouvelle
  /// modification passe alors par la file d'attente, dans l'ordre, jamais par
  /// un appel direct au serveur qui ne connaît pas encore ces changements.
  final bool pendingSync;

  double get total =>
      items.fold(0, (sum, item) => sum + item.quantity * item.unitPrice);

  Map<String, dynamic> toJson() => {
        'id': id,
        'tableId': tableId,
        'status': status,
        'pendingSync': pendingSync,
        'items': items.map((i) => i.toJson()).toList(),
      };

  OrderDetail copyWith({List<OrderItemDetail>? items, bool? pendingSync}) => OrderDetail(
        id: id,
        tableId: tableId,
        status: status,
        items: items ?? this.items,
        pendingSync: pendingSync ?? this.pendingSync,
      );

  factory OrderDetail.fromJson(Map<String, dynamic> json) => OrderDetail(
    id: json['id'] as String,
    tableId: json['tableId'] as String?,
    status: json['status'] as String,
    pendingSync: json['pendingSync'] as bool? ?? false,
    items: (json['items'] as List<dynamic>)
        .map((e) => OrderItemDetail.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
