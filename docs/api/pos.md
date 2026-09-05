# Caisse / POS — Chez Yasmine

## Routes NestJS

```
POST /establishments/:establishmentId/sales                { items, payments, discount?, customerId?, tableId?, orderId? }
GET  /establishments/:establishmentId/sales?day=YYYY-MM-DD
GET  /establishments/:establishmentId/sales/:saleId
POST /establishments/:establishmentId/sales/:saleId/refund
```

`pos.sell` pour créer/consulter, `pos.refund` pour rembourser (permissions distinctes du catalogue de la Phase 3 — un caissier peut vendre sans forcément pouvoir rembourser, selon le rôle).

## Logique métier

Reprise et adaptée du prototype v1 déjà validé :

- `pos-math.ts` : `computeCartTotals` (sous-total, remise en montant ou pourcentage, jamais négative) et `validatePayments` (la somme des paiements doit correspondre exactement au total à ±0,01 près, un paiement crédit exige un client).
- `credit-math.ts` : `applyCreditSale` (plafonne au `creditLimit` du client), partagé avec la Phase 11 (remboursements de crédit).

## `SalesService.create`

1. Recharge les produits **depuis la base**, jamais depuis les prix envoyés par le client — le prix de vente appliqué est toujours `product.salePrice` au moment de la vente.
2. Vérifie le stock disponible pour chaque ligne *avant* d'ouvrir une transaction (échoue vite, sans effet de bord).
3. Calcule les totaux et valide le paiement (fonctions pures ci-dessus).
4. Si un paiement `credit` est présent, vérifie le plafond de crédit du client *avant* la transaction.
5. Transaction Prisma unique : décrémente le stock de chaque produit + écrit un `StockMovement` de type **`sale`** par ligne (jamais accepté sur la route de saisie manuelle du stock, Phase 6) + crée la `Sale`/`SaleItem`/`Payment` + si crédit, crée le `Credit` et met à jour `customer.creditBalance`.

Le nom du produit est recopié dans `SaleItem.name` au moment de la vente (indépendant d'un renommage ultérieur du produit — un reçu ne doit jamais changer rétroactivement).

## `SalesService.refund`

Une vente n'est **jamais supprimée**, seulement marquée `voidedAt` (colonne ajoutée par la migration `20260905210122_add_sale_voided_at.sql`) — piste d'audit conservée. Le remboursement : restocke chaque article (mouvement `in`, motif `Remboursement vente <id>`), et si la vente comportait un paiement crédit, réduit le solde du client du montant crédité pour cette vente précise (clampé à 0, plutôt que de faire échouer un remboursement pour un désalignement comptable mineur — différent d'`applyRepayment`, qui reste strict pour un remboursement volontaire initié par le client).

## UI Flutter

[lib/pos/pos_page.dart](../../apps/web/flutter/lib/pos/pos_page.dart) : cartes produits (recherche + filtre catégorie), panier avec quantités, bouton Encaisser. [lib/pos/payment_dialog.dart](../../apps/web/flutter/lib/pos/payment_dialog.dart) : paiement simple ou mixte (plusieurs lignes cash/Mobile Money/carte — voir note ci-dessous), solde restant affiché en direct. [lib/pos/receipt_page.dart](../../apps/web/flutter/lib/pos/receipt_page.dart) : reçu imprimable à l'écran.

**Le paiement à crédit n'est pas encore exposé dans l'UI** : l'activer correctement nécessite un sélecteur de client, qui est le sujet de la Phase 11 (Clients/Crédits). L'exposer maintenant avec un champ « ID client » en texte libre aurait été une UI trompeuse ; le backend le supporte déjà (`payments: [{ method: 'credit', ... }]`), seule l'interface manque.

## Vérifications effectuées

- `pos-math.ts`/`credit-math.ts` : **testés en conditions réelles** (fonctions pures, sans mock) — 19 tests (totaux de panier, remises, validation de paiement, plafond de crédit, remboursement).
- `SalesService` : testé avec Prisma mocké — refus avant transaction (stock insuffisant, paiement invalide, crédit sans client, plafond dépassé), vente cash complète (stock décrémenté, mouvement `sale` créé), vente à crédit (solde client mis à jour, `Credit` créé), remboursement (restock, `voidedAt`, réversion du crédit).
- UI Flutter : un vrai bug de dépassement visuel (`RenderFlex overflowed`) a été détecté par les tests widget sur le sélecteur de méthode de paiement et corrigé (`isExpanded: true`) — pas seulement un souci de test, un défaut réel qui aurait été visible à l'écran. 3 tests sur le dialogue de paiement (activation du bouton, paiement mixte, suppression d'une ligne).
- **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.
