class StockMovement {
  StockMovement({required this.id, required this.type, required this.quantity, this.reason, required this.createdAt});

  final String id;
  final String type;
  final double quantity;
  final String? reason;
  final DateTime createdAt;

  factory StockMovement.fromJson(Map<String, dynamic> json) => StockMovement(
        id: json['id'] as String,
        type: json['type'] as String,
        quantity: (json['quantity'] as num).toDouble(),
        reason: json['reason'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// Totaux cumulés d'un produit (2026-09-16) : reçue (`in`), consommée
/// (`sale`), perte (`loss`) — voir `StockMovementsService.listMovementTotals`
/// pour la définition exacte de chaque agrégat (`out`/`adjustment` exclus).
class StockMovementTotals {
  StockMovementTotals({required this.productId, required this.received, required this.consumed, required this.lost});

  final String productId;
  final double received;
  final double consumed;
  final double lost;

  factory StockMovementTotals.fromJson(Map<String, dynamic> json) => StockMovementTotals(
        productId: json['productId'] as String,
        received: (json['received'] as num).toDouble(),
        consumed: (json['consumed'] as num).toDouble(),
        lost: (json['lost'] as num).toDouble(),
      );
}

class StockAlert {
  StockAlert({required this.id, required this.name, required this.stockQuantity, required this.minStock});

  final String id;
  final String name;
  final double stockQuantity;
  final double minStock;

  factory StockAlert.fromJson(Map<String, dynamic> json) => StockAlert(
        id: json['id'] as String,
        name: json['name'] as String,
        stockQuantity: (json['stockQuantity'] as num).toDouble(),
        minStock: (json['minStock'] as num).toDouble(),
      );
}

/// Tous les types, pour l'affichage de l'historique — 'loss' y figure encore
/// car les mouvements de type perte existent toujours (écrits par le module
/// Pertes, Phase 12), seule leur *saisie* manuelle a été retirée.
const stockMovementTypeLabels = {
  'in': 'Entrée',
  'out': 'Sortie',
  'adjustment': 'Correction',
  'loss': 'Perte',
};

/// Types acceptés par le dialogue de saisie manuelle — 'loss' est exclu (voir ci-dessus).
const manualStockMovementTypeLabels = {
  'in': 'Entrée',
  'out': 'Sortie',
  'adjustment': 'Correction',
};
