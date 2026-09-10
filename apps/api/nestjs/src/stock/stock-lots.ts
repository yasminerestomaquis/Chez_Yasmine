export type StockLotMovementType = 'in' | 'out' | 'sale' | 'loss' | 'adjustment';

export interface StockLotMovement {
  type: StockLotMovementType;
  quantity: number;
  createdAt: Date;
  /** Motif brut du mouvement (ex. "Commande n°1", "Marché n°2") — seule source dont `referenceNumber` est extrait, voir `parseReferenceNumber`. */
  reason?: string | null;
}

export type StockLotStatus = 'actif' | 'epuise';

export interface StockLot {
  code: string;
  /**
   * N° de commande (achat) ou de marché parsé depuis le motif du mouvement
   * 'in' à l'origine du lot, ou `null` si aucun numéro n'a pu être identifié
   * (mouvement manuel sans motif numéroté, ancien mouvement legacy, etc.).
   * `ChartsService.stockLots` s'en sert pour renuméroter/masquer les lots
   * selon la commande/le marché réellement existant — voir docs/api/charts.md.
   */
  referenceNumber: number | null;
  receivedAt: Date;
  receivedQuantity: number;
  consumedQuantity: number;
  /** Part de `consumedQuantity` imputable à une perte (mouvements 'loss' uniquement), distincte d'une vente ou d'une sortie manuelle. */
  lossQuantity: number;
  remainingQuantity: number;
  status: StockLotStatus;
}

interface WorkingLot {
  receivedAt: Date;
  receivedQuantity: number;
  remainingQuantity: number;
  lossQuantity: number;
  referenceNumber: number | null;
}

/** "Commande n°1", "Correction commande n°1", "Marché n°2" → 1, 1, 2. */
const REFERENCE_NUMBER_PATTERN = /n[°o]\s*(\d+)/i;

function parseReferenceNumber(reason?: string | null): number | null {
  if (!reason) return null;
  const match = REFERENCE_NUMBER_PATTERN.exec(reason);
  return match ? Number(match[1]) : null;
}

/** Consomme `quantity` unités des lots les plus anciens en premier (FIFO), en place. */
function consumeFifo(lots: WorkingLot[], quantity: number, isLoss: boolean): void {
  let remaining = quantity;
  for (const lot of lots) {
    if (remaining <= 0) break;
    const taken = Math.min(lot.remainingQuantity, remaining);
    lot.remainingQuantity -= taken;
    if (isLoss) lot.lossQuantity += taken;
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
 *
 * `code` reste numéroté séquentiellement (L001, L002, ...) dans l'ordre
 * chronologique — comportement historique, conservé tel quel ici pour ne pas
 * casser cette fonction en isolation. `ChartsService.stockLots` est le seul
 * appelant qui a besoin de la correspondance lot↔commande/marché : il lit
 * `referenceNumber` (parsé du motif) pour renuméroter/masquer les lots selon
 * les commandes/marchés réellement existants de l'établissement.
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
          lossQuantity: 0,
          referenceNumber: parseReferenceNumber(movement.reason),
        });
        runningTotal += movement.quantity;
        break;
      case 'out':
        consumeFifo(lots, movement.quantity, false);
        runningTotal -= movement.quantity;
        break;
      case 'sale':
        consumeFifo(lots, movement.quantity, false);
        runningTotal -= movement.quantity;
        break;
      case 'loss':
        consumeFifo(lots, movement.quantity, true);
        runningTotal -= movement.quantity;
        break;
      case 'adjustment': {
        const delta = movement.quantity - runningTotal;
        if (delta > 0) {
          lots.push({
            receivedAt: movement.createdAt,
            receivedQuantity: delta,
            remainingQuantity: delta,
            lossQuantity: 0,
            referenceNumber: parseReferenceNumber(movement.reason),
          });
        } else if (delta < 0) {
          consumeFifo(lots, -delta, false);
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
      referenceNumber: lot.referenceNumber,
      receivedAt: lot.receivedAt,
      receivedQuantity: lot.receivedQuantity,
      consumedQuantity,
      lossQuantity: lot.lossQuantity,
      remainingQuantity: lot.remainingQuantity,
      status: lot.remainingQuantity > 0 ? 'actif' : 'epuise',
    };
  });
}
