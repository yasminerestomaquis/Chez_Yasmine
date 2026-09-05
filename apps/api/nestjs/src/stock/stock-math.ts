/** Manual movement types exposed through the API. 'sale' is written only by the POS flow (Phase 7); 'transfer' awaits multi-establishment support. */
export type ManualStockMovementType = 'in' | 'out' | 'adjustment' | 'loss';

export interface StockMovementInput {
  type: ManualStockMovementType;
  quantity: number;
}

/**
 * Pure stock arithmetic — no I/O, fully unit-tested. Adapted from the
 * equivalent rule already validated in the v1 prototype
 * (docs/superpowers/specs/2026-07-25-maquisbar-pwa-design.md).
 */
export function applyStockMovement(currentQuantity: number, movement: StockMovementInput): number {
  if (!Number.isFinite(movement.quantity) || movement.quantity < 0) {
    throw new Error('quantité invalide pour le mouvement de stock');
  }

  switch (movement.type) {
    case 'in':
      return currentQuantity + movement.quantity;
    case 'out':
    case 'loss': {
      const next = currentQuantity - movement.quantity;
      if (next < 0) {
        throw new Error('stock insuffisant pour ce mouvement');
      }
      return next;
    }
    case 'adjustment':
      return movement.quantity;
    default:
      throw new Error(`type de mouvement inconnu : ${movement.type as string}`);
  }
}

/** minStock defaults to 0 in the database (not nullable) — 0 means "no threshold configured", never an alert. */
export function isLowStock(quantity: number, minStock: number): boolean {
  if (minStock <= 0) return false;
  return quantity <= minStock;
}
