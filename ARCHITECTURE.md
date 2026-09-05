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
| 2026-09-05 | Isolation multi-tenant appliquée par RLS Postgres sur toutes les tables (policies via `organization_id` direct ou fonctions `SECURITY DEFINER` remontant à l'établissement/organisation), en plus du filtrage NestJS | Défense en profondeur (prompt maître §15/§35) ; `service_role` (NestJS) contourne RLS via `BYPASSRLS`, ces policies protègent la clé `anon`/`authenticated` |
| 2026-09-05 | Prisma 7 (dernière version stable, pas la 8.x en release candidate) avec connexion via adaptateur pilote `@prisma/adapter-pg` plutôt que `datasource.url` (retiré du schéma dans cette version) | Prisma 8 restructure entièrement la CLI autour d'une plateforme cloud ("Prisma Developer Platform"), non pertinente ici et encore en RC ; l'API driver-adapter est le mécanisme stable de connexion en Prisma 7 |
| 2026-09-05 | `@nestjs/mau` (CLI de déploiement Nest, scaffoldé par défaut) désinstallé | Non utilisé — déploiement via Docker/GitHub Actions (prompt maître §36/§38) ; éliminait 5 des 9 vulnérabilités `npm audit` initiales sans aucune perte fonctionnelle |
| 2026-09-05 | Auto-inscription du propriétaire : trigger Postgres `handle_new_user` (SECURITY DEFINER) crée organisation + établissement + profil + rôle Propriétaire à l'inscription Supabase Auth, plutôt qu'un endpoint NestJS dédié | Le client ne peut pas créer sa propre organisation via RLS (pas encore de ligne `user_profiles`) ; un trigger côté base est la solution standard Supabase pour ce cas précis, et reste cohérent avec « toute donnée métier rattachée à son organisation » (prompt maître §15). Portée limitée à l'auto-inscription — l'invitation d'utilisateurs est un flux distinct, non traité |
| 2026-09-05 | Vérification JWT NestJS via JWKS (`jose`), confirmé après avoir interrogé l'endpoint `.well-known/jwks.json` réel du projet (signature ES256) | Le prompt maître demandait explicitement JWKS plutôt qu'un secret partagé JWT ; confirmé que le projet Supabase utilise bien les clés de signature asymétriques modernes, pas l'ancien secret HS256 |
| 2026-09-05 | Upload des photos produit vers Supabase Storage avec le jeton JWT de l'utilisateur authentifié (propagé depuis `SupabaseJwtGuard`), pas une clé `service_role` | Évite d'introduire un nouveau secret côté NestJS pour cet usage ; la RLS de `storage.objects` (identique au modèle des tables) suffit à garantir l'isolation, cohérent avec la défense en profondeur déjà en place |
| 2026-09-05 | Bucket `product-images` privé (pas de fichiers publics) ; l'accès se fait via URL signée à durée limitée générée à la demande par NestJS | Le prompt maître interdit de faire confiance au client ; une URL publique permanente contournerait entièrement la RLS Storage |
| 2026-09-05 | Le type de mouvement de stock `sale` n'est jamais accepté sur la route de saisie manuelle (`in`/`out`/`adjustment`/`loss` seulement) | Une vente doit rester la seule origine possible d'un mouvement `sale`, écrit automatiquement par le flux caisse (Phase 7) — l'exposer en saisie manuelle permettrait de fausser les statistiques de vente sans transaction réelle |
| 2026-09-05 | Une vente n'est jamais supprimée : un remboursement marque `voidedAt` et restocke, sans effacer la ligne | Piste d'audit obligatoire sur une opération financière (prompt maître §35, §44) ; une suppression effacerait toute trace comptable de la transaction d'origine |
| 2026-09-05 | Le paiement à crédit n'est pas exposé dans l'UI caisse tant que la gestion des clients (Phase 11) n'existe pas | Un champ « ID client » en texte libre serait une UI trompeuse ; le backend le supporte déjà, seul le sélecteur de client manque |
| 2026-09-05 | La règle « une seule addition ouverte par table » n'est imposée qu'au niveau applicatif (`openTable`), pas par une contrainte de base de données ; `split` la contourne délibérément | Diviser une addition entre deux groupes assis à la même table doit rester possible sans déplacer physiquement personne — une contrainte DB stricte l'aurait empêché |

## Points ouverts (nécessitent une décision ou une action ultérieure)

- **Push GitHub** : le remote `origin` (`https://github.com/yasminerestomaquis/Chez_Yasmine.git`) est configuré, mais le compte `gh` authentifié localement (`Autocad-Qgis`) n'a pas les droits de push sur ce dépôt qui appartient au compte `yasminerestomaquis`. À résoudre avant le premier push (ré-authentification `gh auth login` sous le bon compte, jeton d'accès personnel du compte `yasminerestomaquis`, ou ajout d'`Autocad-Qgis` comme collaborateur).
- **Docker / Supabase CLI locaux** : Docker non installé sur cette machine (build de `docker/Dockerfile.nestjs` non testé localement). Supabase CLI utilisable à la demande via `npx supabase@latest` (sans installation globale) mais `supabase start` (stack locale complète) nécessite Docker et n'a pas été utilisé — le développement contre Supabase se fait via les outils MCP (migrations, SQL, Storage).
- **`DATABASE_URL` réel non disponible** : les migrations ont été appliquées via l'API de gestion Supabase (MCP), pas via une connexion Postgres directe. Le mot de passe de connexion (nécessaire pour `prisma db pull`, `prisma migrate dev`, et pour que l'API NestJS tourne réellement) doit être récupéré depuis le dashboard Supabase et renseigné dans `.env`.
- **`npm audit`** : 4 vulnérabilités high résiduelles dans `apps/api/nestjs`, toutes transitives au *CLI* Prisma 7.10.0 (`deepmerge-ts`, `mysql2` via `@prisma/config`) — pas dans le client généré ni le code applicatif. Le correctif automatique rétrograderait vers `prisma@6.19.3` ; accepté pour l'instant, à réévaluer à la prochaine release stable de Prisma.
- **Schéma de base de données** (Phase 3) : conçu et appliqué (voir `docs/database/schema.md`). Reste à faire : brancher Prisma sur une vraie connexion (`DATABASE_URL`), et construire les modules NestJS (services/repositories) qui l'utilisent — pas encore commencé (Phase 5+).
