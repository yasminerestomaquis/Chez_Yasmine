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
