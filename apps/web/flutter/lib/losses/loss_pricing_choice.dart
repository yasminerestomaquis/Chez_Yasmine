import 'package:flutter/material.dart';

import '../catalog/models.dart';
import '../common/formatting.dart';

/// Vrai si le produit se vend par lot ET à l'unité (`unitSalePrice` renseigné
/// et `salePrice` = prix du lot) : la perte propose alors le choix Lot/Unité,
/// comme « Comment vendre ce produit ? » en caisse.
///
/// Un lot d'UNE seule unité (`Product.isSoldAsSingleUnitOnly`, « Lot (1) » =
/// « Unité ») n'offre pas de vrai choix : même règle qu'en Caisse/Tables
/// (demande du 2026-10-07), voir [lossSellsAsUnit].
bool hasLotAndUnitPricing(Product? product) =>
    product != null && product.unitSalePrice != null && product.salePrice != null && !product.isSoldAsSingleUnitOnly;

/// Valorisation « Unité » d'une perte : imposée pour un lot d'une seule unité,
/// sinon selon le choix de l'utilisateur (si le produit propose le choix).
bool lossSellsAsUnit(Product? product, bool chosenUnit) =>
    product != null && (product.isSoldAsSingleUnitOnly || (chosenUnit && hasLotAndUnitPricing(product)));

/// Libellé de l'option Lot (ex. « Lot (3) — 2 000 FCFA »).
String lossLotLabel(Product product) {
  final unit = product.unit;
  final prefix = unit == null || unit.trim().isEmpty ? 'Lot' : 'Lot ($unit)';
  return '$prefix — ${formatAmount(product.salePrice!)} FCFA';
}

/// Libellé de l'option Unité (ex. « Unité — 700 FCFA »).
String lossUnitLabel(Product product) => 'Unité — ${formatAmount(product.unitSalePrice!)} FCFA';

/// Choix Lot / Unité d'une perte (valorisation uniquement).
class LossPricingChoice extends StatelessWidget {
  const LossPricingChoice({super.key, required this.product, required this.sellAsUnit, required this.onChanged});

  final Product product;
  final bool sellAsUnit;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Prix de la perte'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ChoiceChip(label: Text(lossLotLabel(product)), selected: !sellAsUnit, onSelected: (_) => onChanged(false)),
            ChoiceChip(label: Text(lossUnitLabel(product)), selected: sellAsUnit, onSelected: (_) => onChanged(true)),
          ],
        ),
      ],
    );
  }
}
