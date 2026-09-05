# ARCHITECTURE.md — Chez Yasmine (MaquisBar)

## Vue d'ensemble

```
                         UTILISATEURS
                              │
                              ▼
                    ┌───────────────────┐
                    │   Chez Yasmine    │
                    │       PWA         │
                    │    Flutter Web    │
                    └─────────┬─────────┘
                              │
                         HTTPS / REST
                        (WebSocket si besoin)
                              │
                              ▼
                    ┌───────────────────┐
                    │    NestJS API     │
                    │                   │
                    │ Business Logic    │
                    │ RBAC              │
                    │ Validation        │
                    │ Transactions      │
                    │ Synchronisation   │
                    └─────────┬─────────┘
                              │
                              ▼
                       ┌──────────────┐
                       │   SUPABASE   │
                       ├──────────────┤
                       │ PostgreSQL   │
                       │ Storage      │
                       │ Auth         │
                       │ RLS          │
                       └──────────────┘
```

Le client Flutter n'est jamais une source de confiance : toute opération métier critique (vente, paiement, remboursement, mouvement de stock, perte, clôture de caisse, crédit, modification financière) est validée et exécutée par NestJS, pas directement par le client contre Postgres.

## Responsabilités par composant

**Flutter / PWA** — interface, navigation, responsive design, catalogue, caisse, tables, cache local, fonctionnement hors ligne, synchronisation côté client, installation PWA.

**NestJS** — logique métier, API, validation, autorisation (RBAC), règles métier, transactions, calculs, ventes, stock, paiements, clôtures, audit, synchronisation serveur, WebSocket si nécessaire. Vérifie les JWT émis par Supabase Auth.

**Supabase** — PostgreSQL, stockage des images/fichiers, RLS, authentification, fonctions Postgres lorsque pertinent.

**GitHub** — dépôt, branches, PR, issues, releases, GitHub Actions (CI/CD), secrets.

## Multi-tenant

```
Organisation
    │
    ├── Établissement
    │      ├── Point de vente
    │      ├── Produits
    │      ├── Stocks
    │      └── Utilisateurs
    │
    └── Utilisateurs
```

Isolation garantie à trois niveaux : filtrage systématique par `organization_id` côté NestJS, RLS Postgres, et policies Storage. Un utilisateur ne doit jamais pouvoir accéder aux données d'une autre organisation.

## Modèle de données (cible, avant migrations)

`Organization, Establishment, PointOfSale, User, Role, Permission, RolePermission, Category, Product, ProductImage, StockMovement, Supplier, Purchase, PurchaseItem, Table, Reservation, Order, OrderItem, Sale, SaleItem, Payment, Customer, Credit, CreditPayment, Loss, Expense, CashRegister, CashClosing, AccountingEntry, ServerCommission, Notification, Subscription, SyncOperation, AuditLog`

UUID pour tous les identifiants. Détail des colonnes/relations à formaliser en Phase 3 (`docs/database/`).

## Décisions architecturales actées

| Date | Décision | Justification |
|---|---|---|
| 2026-09-05 | Adoption intégrale de l'architecture v5 (Flutter + NestJS + Supabase, SaaS multi-tenant) en remplacement du prototype v1 (React/Vite/Dexie, mono-site local) | Choix explicite de l'utilisateur (« Considère le V5 ») |
| 2026-09-05 | Authentification : Supabase Auth comme fournisseur d'identité unique ; NestJS vérifie le JWT Supabase et applique RBAC/règles métier par-dessus | Évite une double authentification Supabase/NestJS (cf. prompt maître §29) ; validé explicitement par l'utilisateur |
| 2026-09-05 | Monorepo hébergé dans le dépôt existant `D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT` (structure `apps/`, `packages/`, `supabase/` ajoutée à côté de l'historique `PROMPT/`, `docs/`) | Conserve l'historique Git et les décisions déjà prises plutôt que de repartir d'un dépôt vide |
| 2026-09-05 | Réutilisation du projet Supabase déjà créé par l'utilisateur (`yasminerestomaquis's Project`, `tsebsulvhgttdwtgqfoj`, eu-west-1, Postgres 17, vierge) | Le projet existait déjà et est vide — aucune raison d'en créer un second |
| 2026-09-05 | Le prototype v1 (`worktree-maquisbar-v1`) est conservé tel quel comme référence de règles métier, non supprimé, non repris comme base de code du produit final | Règle « ne pas supprimer une fonctionnalité/du travail existant sans justification » (prompt maître §43) |
| 2026-09-05 | SDK Flutter installé localement via clonage Git du dépôt officiel (`flutter/flutter`, branche `stable`) dans `C:\flutter`, faute de paquet winget officiel | Choix explicite de l'utilisateur (installer Flutter maintenant) ; winget ne référence pas le SDK Flutter lui-même |

## Points ouverts (nécessitent une décision ou une action ultérieure)

- **Push GitHub** : le remote `origin` (`https://github.com/yasminerestomaquis/Chez_Yasmine.git`) est configuré, mais le compte `gh` authentifié localement (`Autocad-Qgis`) n'a pas les droits de push sur ce dépôt qui appartient au compte `yasminerestomaquis`. À résoudre avant le premier push (ré-authentification `gh auth login` sous le bon compte, jeton d'accès personnel du compte `yasminerestomaquis`, ou ajout d'`Autocad-Qgis` comme collaborateur).
- **Docker / Supabase CLI locaux** : non installés sur cette machine. Le développement contre Supabase se fait via les outils MCP Supabase (migrations, SQL, Storage) plutôt que via `supabase start` local. À réévaluer si un environnement 100 % local (offline du poste de dev) devient nécessaire.
- **Schéma de base de données détaillé** (Phase 3) : à concevoir et migrer via `supabase/migrations/` — non commencé.
