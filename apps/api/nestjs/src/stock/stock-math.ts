/** 'sale' is written only by the POS flow (Phase 7); 'loss' only by the Losses flow (Phase 12, `src/losses/`); 'transfer' awaits multi-establishment support. 'loss' stays a case of this shared type/arithmetic even though it's no longer accepted on the manual stock-movement endpoint (see CreateStockMovementDto) — LossesService reuses the same math. */
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
