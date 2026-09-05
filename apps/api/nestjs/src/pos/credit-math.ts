/** Pure credit-account arithmetic — adapted from the already-validated v1 prototype (credit.ts). Reused by POS (credit sales) and Phase 11 (repayments). */

export interface CreditAccount {
  balance: number;
  limit: number;
}

export function applyCreditSale(account: CreditAccount, amount: number): number {
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new Error('montant invalide pour la vente à crédit');
  }
  const next = account.balance + amount;
  if (next > account.limit) {
    throw new Error('plafond de crédit dépassé');
  }
  return next;
}

export function applyRepayment(currentBalance: number, amount: number): number {
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new Error('montant invalide pour le remboursement');
  }
  if (amount > currentBalance) {
    throw new Error('remboursement supérieur au solde');
  }
  return currentBalance - amount;
}
