/** Pure caisse arithmetic — adapted from the already-validated v1 prototype (cart.ts / payment.ts). */

export interface CartLine {
  productId: string;
  unitPrice: number;
  quantity: number;
}

export type Discount = { type: 'amount'; value: number } | { type: 'percent'; value: number };

export interface CartTotals {
  subtotal: number;
  discount: number;
  total: number;
}

function lineTotal(line: CartLine): number {
  if (!Number.isFinite(line.quantity) || line.quantity <= 0) {
    throw new Error(`quantité invalide pour le produit ${line.productId}`);
  }
  return line.unitPrice * line.quantity;
}

export function computeCartTotals(lines: CartLine[], discount: Discount): CartTotals {
  if (lines.length === 0) {
    throw new Error('le panier est vide');
  }
  const subtotal = lines.reduce((sum, line) => sum + lineTotal(line), 0);
  const rawDiscount = discount.type === 'percent' ? subtotal * (discount.value / 100) : discount.value;
  const clampedDiscount = Math.max(0, Math.min(rawDiscount, subtotal));
  return { subtotal, discount: clampedDiscount, total: subtotal - clampedDiscount };
}

export type PaymentMethod = 'cash' | 'mobile_money' | 'card' | 'credit';

export interface PaymentInput {
  method: PaymentMethod;
  amount: number;
}

export interface PaymentContext {
  customerId?: string;
}

const EPSILON = 0.01;

export function validatePayments(payments: PaymentInput[], total: number, context?: PaymentContext): void {
  if (payments.length === 0) {
    throw new Error('paiement incomplet : aucune ligne de paiement');
  }
  for (const payment of payments) {
    if (!Number.isFinite(payment.amount) || payment.amount <= 0) {
      throw new Error(`montant invalide pour le paiement ${payment.method}`);
    }
  }
  const hasCredit = payments.some((p) => p.method === 'credit');
  if (hasCredit && !context?.customerId) {
    throw new Error('client requis pour une vente à crédit');
  }
  const sum = payments.reduce((acc, p) => acc + p.amount, 0);
  if (Math.abs(sum - total) > EPSILON) {
    throw new Error(`paiement incomplet : ${sum} reçu pour un total de ${total}`);
  }
}
