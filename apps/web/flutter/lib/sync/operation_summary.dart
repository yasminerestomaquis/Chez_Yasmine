import '../common/formatting.dart';
import 'pending_operation.dart';

double _sum(Object? list, String key) {
  if (list is! List) return 0;
  var total = 0.0;
  for (final item in list) {
    if (item is Map && item[key] is num) total += (item[key] as num).toDouble();
  }
  return total;
}

String _quantity(Object? value) {
  if (value is! num) return '?';
  return value == value.roundToDouble() ? value.toInt().toString() : value.toString();
}

/// Libellé court, lisible par un utilisateur, d'une opération en attente ou à
/// corriger — la liste « à corriger » ne montre que ce que la charge utile
/// permet de dire (le nom d'un produit, par exemple, n'y figure pas).
String describeOperation(PendingOperation operation) {
  final p = operation.payload;
  switch (operation.entityType) {
    case 'sale':
      final amount = formatAmount(_sum(p['payments'], 'amount'));
      return p['orderId'] != null ? 'Encaissement d\'une addition — $amount FCFA' : 'Vente — $amount FCFA';
    case 'stock_movement':
      const labels = {'in': 'Entrée', 'out': 'Sortie', 'adjustment': 'Correction'};
      return '${labels[p['type']] ?? 'Mouvement'} de stock — quantité ${_quantity(p['quantity'])}';
    case 'expense':
      final label = p['label'];
      final amount = p['amount'] is num ? ' (${formatAmount(p['amount'] as num)} FCFA)' : '';
      return 'Dépense — ${label ?? 'sans libellé'}$amount';
    case 'loss':
      return 'Perte — quantité ${_quantity(p['quantity'])}';
    case 'purchase':
      return 'Commande d\'achat n°${p['orderNumber'] ?? '?'}';
    case 'order_open':
      final guests = p['guestCount'] is num ? ' (${_quantity(p['guestCount'])} couverts)' : '';
      return 'Ouverture de table$guests';
    case 'order_item_add':
      return 'Ajout à une addition — ${p['productName'] ?? 'article'}';
    case 'order_item_set':
      return 'Quantité modifiée sur une addition — ${p['productName'] ?? 'article'} '
          '(${_quantity(p['expectedQuantity'])} → ${_quantity(p['quantity'])})';
    case 'order_item_remove':
      return 'Retrait d\'une addition — ${p['productName'] ?? 'article'}';
    case 'cash_closing':
      final counted = p['countedAmount'] is num ? ' — compté ${formatAmount(p['countedAmount'] as num)} FCFA' : '';
      return 'Clôture de caisse$counted';
    default:
      return operation.entityType;
  }
}
