# Caisse / POS — Chez Yasmine

## Routes NestJS

```
POST /establishments/:establishmentId/sales                     { items, payments, discount?, customerId?, tableId?, orderId?, orderNumber?, marketNumber? }
GET  /establishments/:establishmentId/sales?day=YYYY-MM-DD
GET  /establishments/:establishmentId/sales/last-order-number   { orderNumber: number | null }  — suggestion, jamais imposée
GET  /establishments/:establishmentId/sales/last-market-number  { marketNumber: number | null }  — suggestion, jamais imposée
GET  /establishments/:establishmentId/sales/:saleId
POST /establishments/:establishmentId/sales/:saleId/refund
```

`pos.sell` pour créer/consulter, `pos.refund` pour rembourser (permissions distinctes du catalogue de la Phase 3 — un caissier peut vendre sans forcément pouvoir rembourser, selon le rôle).

## Logique métier

Reprise et adaptée du prototype v1 déjà validé :

- `pos-math.ts` : `computeCartTotals` (sous-total, remise en montant ou pourcentage, jamais négative) et `validatePayments` (la somme des paiements doit correspondre exactement au total à ±0,01 près, un paiement crédit exige un client).
- `credit-math.ts` : `applyCreditSale` (plafonne au `creditLimit` du client), partagé avec la Phase 11 (remboursements de crédit).

## `SalesService.create`

1. Recharge les produits **depuis la base**, jamais depuis les prix envoyés par le client — le prix de vente appliqué est toujours `product.salePrice` au moment de la vente, **sauf** pour un produit d'une catégorie à prix variable (`Category.hasVariablePricing`, ex. Poulets/Poissons/Plats africains — voir `docs/api/catalog.md`) : `product.salePrice` y est `null` en catalogue, donc le caissier saisit un prix dans l'UI (`PosPage._promptManualPrice`), transmis en `SaleItemDto.unitPrice` ; le serveur l'exige dans ce cas (`BadRequestException` sinon) et l'ignore pour tout autre produit — le client ne devient jamais source de vérité sur le prix d'un produit à prix fixe, défense en profondeur cohérente avec le reste de l'application (CLAUDE.md, « le client n'est jamais une source de confiance »).
2. Vérifie le stock disponible pour chaque ligne *avant* d'ouvrir une transaction (échoue vite, sans effet de bord).
3. Calcule les totaux et valide le paiement (fonctions pures ci-dessus).
4. Si un paiement `credit` est présent, vérifie le plafond de crédit du client *avant* la transaction.
5. Transaction Prisma unique : décrémente le stock de chaque produit + écrit un `StockMovement` de type **`sale`** par ligne (jamais accepté sur la route de saisie manuelle du stock, Phase 6) + crée la `Sale`/`SaleItem`/`Payment` + si crédit, crée le `Credit` et met à jour `customer.creditBalance`.

Le nom du produit est recopié dans `SaleItem.name` au moment de la vente (indépendant d'un renommage ultérieur du produit — un reçu ne doit jamais changer rétroactivement).

## N° de commande / N° de marché (décision actée 2026-09-10)

Chaque vente peut porter un `orderNumber` (Bières/Vins/Sucreries — rattachement à `Purchase.orderNumber`) et/ou un `marketNumber` (Poulets/Poissons/Plats africains — rattachement à `Expense.marketNumber`), saisis dans le sous-formulaire Paiement — commun à la Caisse (`pos_page.dart`) et à une addition de Table (`table_order_page.dart`, même `showPaymentDialog`/`fetchLastOrderNumber`/`fetchLastMarketNumber`, aucune différence entre les deux écrans) : un seul champ de chaque, pour **toute la vente**, jamais par ligne — si le panier mélange les deux groupes, les deux champs s'affichent ensemble. Comme `Purchase.orderNumber`/`Expense.marketNumber`, ce sont de simples suggestions éditables (`GET .../sales/last-order-number`/`last-market-number`, jamais imposées ni vérifiées contre une commande/dépense existante) — `CreateSaleDto` les accepte en option et `SalesService.create` les écrit telles quelles sur `Sale.orderNumber`/`Sale.marketNumber` (migration `20260910200000_add_sale_order_market_number.sql`). Objectif : permettre de déterminer a posteriori, hors périmètre de cette phase, le bénéfice réalisé par commande/marché plutôt que seulement de façon agrégée.

Repli intentionnel si la suggestion échoue (hors ligne, permission manquante) : le champ reste vide mais éditable, jamais bloquant — même principe que `PurchasesService.nextOrderNumber`.

**Correctif (2026-09-13)** : `lastOrderNumber`/`lastMarketNumber` triaient par `createdAt` décroissant (la ligne la plus récemment **insérée**) plutôt que par le numéro lui-même — or une commande d'achat ou une dépense « Marché » peut être saisie après coup (date librement modifiable, voir `docs/api/purchasing.md`/`docs/api/expenses.md`), donc l'ordre d'insertion ne reflète pas forcément le numéro le plus élevé réellement en usage. Corrigé pour trier par `orderNumber`/`marketNumber` décroissant, exactement comme `PurchasesService.nextOrderNumber`/`ExpensesService.nextMarketNumber` le font déjà côté suggestion de **nouveau** numéro — les deux mécanismes utilisent maintenant la même convention. `lastMarketNumber` exclut aussi explicitement les dépenses « Marché » sans numéro renseigné (`marketNumber: { not: null }`, un champ non obligatoire même pour cette nature).

## `SalesService.refund`

Une vente n'est **jamais supprimée**, seulement marquée `voidedAt` (colonne ajoutée par la migration `20260905210122_add_sale_voided_at.sql`) — piste d'audit conservée. Le remboursement : restocke chaque article (mouvement `in`, motif `Remboursement vente <id>`), et si la vente comportait un paiement crédit, réduit le solde du client du montant crédité pour cette vente précise (clampé à 0, plutôt que de faire échouer un remboursement pour un désalignement comptable mineur — différent d'`applyRepayment`, qui reste strict pour un remboursement volontaire initié par le client).

## UI Flutter

[lib/pos/pos_page.dart](../../apps/web/flutter/lib/pos/pos_page.dart) : cartes produits (recherche + filtre catégorie), panier avec quantités, bouton Encaisser. [lib/pos/payment_dialog.dart](../../apps/web/flutter/lib/pos/payment_dialog.dart) : paiement simple ou mixte (plusieurs lignes Espèces/Mobile Money — Carte/Crédit retirés le 2026-09-10, voir `CHANGELOG.md`), champs N° de commande/N° de marché conditionnels (voir ci-dessus), solde restant affiché en direct. [lib/pos/receipt_page.dart](../../apps/web/flutter/lib/pos/receipt_page.dart) : reçu imprimable à l'écran.

**Un seul bouton « Valider le paiement » (décision utilisateur du 2026-09-13)** : le bouton distinct « Ajouter la ligne de paiement » a été retiré — pour un paiement à un seul mode (l'écrasante majorité des cas), le montant est déjà pré-rempli au total, donc un seul clic sur « Valider le paiement » enregistre la ligne et ferme aussitôt le dialogue. Le bouton reste toujours actif (plus besoin d'atteindre un solde nul au préalable). Un paiement fractionné reste possible sans bouton dédié : tant qu'un solde subsiste après avoir enregistré la ligne courante, le dialogue reste ouvert (montant suivant pré-rempli avec ce solde) pour la ligne suivante — le nombre de clics pour un paiement fractionné est inchangé, seul le bouton « Ajouter la ligne » distinct a disparu.

**Le paiement à crédit n'est pas encore exposé dans l'UI** : l'activer correctement nécessite un sélecteur de client, qui est le sujet de la Phase 11 (Clients/Crédits). L'exposer maintenant avec un champ « ID client » en texte libre aurait été une UI trompeuse ; le backend le supporte déjà (`payments: [{ method: 'credit', ... }]`), seule l'interface manque.

## Vérifications effectuées

- `pos-math.ts`/`credit-math.ts` : **testés en conditions réelles** (fonctions pures, sans mock) — 19 tests (totaux de panier, remises, validation de paiement, plafond de crédit, remboursement).
- `SalesService` : testé avec Prisma mocké — refus avant transaction (stock insuffisant, paiement invalide, crédit sans client, plafond dépassé), vente cash complète (stock décrémenté, mouvement `sale` créé), vente à crédit (solde client mis à jour, `Credit` créé), remboursement (restock, `voidedAt`, réversion du crédit), produit à prix variable (refus sans `unitPrice`, prix saisi repris dans les totaux et le `SaleItem`, `unitPrice` client ignoré pour un produit à prix fixe), transmission de `orderNumber`/`marketNumber`, `lastOrderNumber`/`lastMarketNumber` (null si aucun, sinon le plus élevé — pas le plus récemment créé).
- UI Flutter : un vrai bug de dépassement visuel (`RenderFlex overflowed`) a été détecté par les tests widget sur le sélecteur de méthode de paiement et corrigé (`isExpanded: true`) — pas seulement un souci de test, un défaut réel qui aurait été visible à l'écran. 5 tests sur le dialogue de paiement (2026-09-13 : bouton toujours actif, paiement complet en un clic, paiement mixte via le bouton unique, suppression d'une ligne — remplacent les 3 tests d'origine construits autour du bouton « Ajouter la ligne » disparu).
- **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.
