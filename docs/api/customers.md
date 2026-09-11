# Clients / Crédits — Chez Yasmine

## Routes NestJS

```
GET    /establishments/:establishmentId/customers                              (customers.manage)
POST   /establishments/:establishmentId/customers                              (customers.manage)
PATCH  /establishments/:establishmentId/customers/:customerId                  (customers.manage)
DELETE /establishments/:establishmentId/customers/:customerId                  (customers.manage)

GET    /establishments/:establishmentId/customers/:customerId/credit/history   (credits.manage)
POST   /establishments/:establishmentId/customers/:customerId/credit/payments  (credits.manage)
```

Deux permissions distinctes (déjà dans le seed de la Phase 3) : la fiche client (`customers.manage`, accessible au Caissier) et le crédit (`credits.manage`, réservé au Comptable/Propriétaire/Gérant) ne sont pas gérés par les mêmes rôles.

## Historique de crédit

`CreditsService.history` fusionne les lignes `Credit` (ventes à crédit, créées automatiquement par `SalesService` en Phase 7) et `CreditPayment` (remboursements volontaires) en une seule chronologie, triée du plus récent au plus ancien.

## Remboursement

`CreditsService.recordRepayment` réutilise `applyRepayment` (déjà écrite et testée en Phase 7, partagée depuis `pos/credit-math.ts`) : rejette un remboursement supérieur au solde actuel — **strict**, contrairement au remboursement automatique et clampé de `SalesService.refund` (Phase 7), qui ne doit jamais faire échouer l'annulation d'une vente pour un désalignement comptable mineur. Un remboursement volontaire, lui, doit être rejeté s'il ne correspond pas à un solde réel.

## Le paiement à crédit, enfin activé en caisse

Les Phases 7 et 8 avaient délibérément laissé le paiement à crédit hors de l'UI, faute de sélecteur de client. `PaymentDialog` ([lib/pos/payment_dialog.dart](../../apps/web/flutter/lib/pos/payment_dialog.dart)) charge maintenant la liste des clients dès que la méthode « Crédit » est choisie, et exige d'en sélectionner un avant d'accepter la ligne de paiement. Le résultat (`PaymentOutcome`) porte désormais `customerId` en plus des lignes de paiement, propagé jusqu'à `PosPage`/`TableOrderPage` (anciennement `OrderDetailPage`, remplacé le 2026-09-10) puis à `SalesService.create`.

Limite connue : si une vente comportait plusieurs lignes crédit avec des clients différents (cas d'usage marginal, non empêché par l'UI), seul le dernier client sélectionné est retenu — acceptable pour le cas réel (un seul client à crédit par vente).

## Vérifications effectuées

- `CreditsService` : testé avec Prisma mocké — 4 tests (fusion de l'historique et tri, rejet d'un remboursement supérieur au solde avant toute écriture, mise à jour correcte du solde et création du paiement).
- UI Flutter : `flutter analyze`/`flutter test`/`flutter build web` ✅, y compris un test widget vérifiant que la ligne de paiement à crédit reste bloquée tant qu'aucun client n'est sélectionné (avec gestion défensive de l'échec de chargement de la liste clients, affichée dans le dialogue plutôt que via `ScaffoldMessenger` pour ne pas dépendre d'un `Scaffold` ancêtre).
- **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.
