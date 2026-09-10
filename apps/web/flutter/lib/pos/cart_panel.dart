import 'package:flutter/material.dart';

import '../common/formatting.dart';
import '../theme/app_theme.dart';

/// Panneau panier — partagé entre `PosPage` (panier local, `T = CartLine`) et
/// l'écran de table (`T = OrderItemDetail`, panier persisté serveur). Générique
/// sur le type de ligne pour ne pas imposer de forme de données commune :
/// chaque appelant fournit juste comment en extraire nom/quantité/prix, et
/// récupère l'objet d'origine dans `onChangeQuantity` pour agir dessus à sa
/// façon (mutation locale pour la Caisse, appel serveur pour la table).
class CartPanel<T> extends StatelessWidget {
  const CartPanel({
    super.key,
    required this.lines,
    required this.nameOf,
    required this.quantityOf,
    required this.unitPriceOf,
    required this.subtotal,
    required this.isCharging,
    required this.onChangeQuantity,
    required this.onCheckout,
    this.scrollController,
  });

  final List<T> lines;
  final String Function(T line) nameOf;
  final double Function(T line) quantityOf;
  final double Function(T line) unitPriceOf;
  final double subtotal;
  final bool isCharging;
  final void Function(T line, int delta) onChangeQuantity;
  final VoidCallback onCheckout;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (scrollController != null)
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: SizedBox(width: 36, child: Divider(thickness: 4, height: 4)),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              const Text(
                'Panier',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              if (scrollController != null)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
            ],
          ),
        ),
        Expanded(
          child: lines.isEmpty
              ? const Center(child: Text('Panier vide'))
              : ListView(
                  controller: scrollController,
                  children: [
                    for (final line in lines)
                      ListTile(
                        title: Text(nameOf(line)),
                        subtitle: Text(
                          '${formatAmount(unitPriceOf(line))} FCFA x ${quantityOf(line).toStringAsFixed(0)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: AppColors.alert,
                              ),
                              onPressed: () => onChangeQuantity(line, -1),
                            ),
                            Text(quantityOf(line).toStringAsFixed(0)),
                            IconButton(
                              icon: const Icon(
                                Icons.add_circle_outline,
                                color: AppColors.green,
                              ),
                              onPressed: () => onChangeQuantity(line, 1),
                            ),
                          ],
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
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const Spacer(),
                  Text(
                    '${formatAmount(subtotal)} FCFA',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: lines.isEmpty || isCharging ? null : onCheckout,
                child: isCharging
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Encaisser'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
