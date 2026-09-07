export type StockLotMovementType = 'in' | 'out' | 'sale' | 'loss' | 'adjustment';

export interface StockLotMovement {
  type: StockLotMovementType;
  quantity: number;
  createdAt: Date;
}

export type StockLotStatus = 'actif' | 'epuise';

export interface StockLot {
  code: string;
  receivedAt: Date;
  receivedQuantity: number;
  consumedQuantity: number;
  remainingQuantity: number;
  status: StockLotStatus;
}

interface WorkingLot {
  receivedAt: Date;
  receivedQuantity: number;
  remainingQuantity: number;
}

/** Consomme `quantity` unités des lots les plus anciens en premier (FIFO), en place. */
function consumeFifo(lots: WorkingLot[], quantity: number): void {
  let remaining = quantity;
  for (const lot of lots) {
    if (remaining <= 0) break;
    const taken = Math.min(lot.remainingQuantity, remaining);
    lot.remainingQuantity -= taken;
    remaining -= taken;
  }
}

/**
 * Reconstruit les lots FIFO d'un produit à partir de son historique brut de
 * `StockMovement`, sans schéma dédié : chaque mouvement 'in' (réception
 * d'achat, remboursement de vente) devient un lot indépendant portant sa
 * propre quantité restante ; chaque mouvement de sortie ('out', 'sale',
 * 'loss') est imputé aux lots existants du plus ancien au plus récent,
 * exactement comme `applyStockMovement` (../stock/stock-math.ts) impute ces
 * mêmes mouvements au compteur `product.stockQuantity` — cette fonction ne
 * fait qu'exploser ce compteur en tranches datées, elle ne recalcule rien
 * d'autre. Un lot dont la quantité restante atteint 0 devient « épuisé » et
 * disparaît des lots actifs, mais reste dans la liste complète (traçabilité).
 *
 * 'adjustment' est un cas particulier : ce mouvement fixe une quantité
 * absolue plutôt que relative (voir stock-math.ts), donc il ne correspond ni
 * à une entrée ni à une sortie franche. Traité ici comme la différence avec
 * le total couru : une hausse crée un lot synthétique daté de l'ajustement,
 * une baisse consomme les lots existants en FIFO — ce qui préserve
 * l'invariant « somme des quantités restantes des lots == product.stockQuantity »
 * même en présence de corrections manuelles.
 */
export function computeFifoLots(movements: StockLotMovement[]): StockLot[] {
  const ordered = [...movements].sort((a, b) => a.createdAt.getTime() - b.createdAt.getTime());
  const lots: WorkingLot[] = [];
  let runningTotal = 0;

  for (const movement of ordered) {
    switch (movement.type) {
      case 'in':
        lots.push({
          receivedAt: movement.createdAt,
          receivedQuantity: movement.quantity,
          remainingQuantity: movement.quantity,
        });
        runningTotal += movement.quantity;
        break;
      case 'out':
      case 'sale':
      case 'loss':
        consumeFifo(lots, movement.quantity);
        runningTotal -= movement.quantity;
        break;
      case 'adjustment': {
        const delta = movement.quantity - runningTotal;
        if (delta > 0) {
          lots.push({ receivedAt: movement.createdAt, receivedQuantity: delta, remainingQuantity: delta });
        } else if (delta < 0) {
          consumeFifo(lots, -delta);
        }
        runningTotal = movement.quantity;
        break;
      }
    }
  }

  return lots.map((lot, index) => {
    const consumedQuantity = lot.receivedQuantity - lot.remainingQuantity;
    return {
      code: `L${String(index + 1).padStart(3, '0')}`,
      receivedAt: lot.receivedAt,
      receivedQuantity: lot.receivedQuantity,
      consumedQuantity,
      remainingQuantity: lot.remainingQuantity,
      status: lot.remainingQuantity > 0 ? 'actif' : 'epuise',
    };
  });
}
