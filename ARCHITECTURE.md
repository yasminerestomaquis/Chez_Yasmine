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
| 2026-09-05 | L'idempotence des opérations critiques repose sur un `id` généré côté client, réutilisé comme id de l'entité serveur (`Sale.id`, `StockMovement.id`) — pas un identifiant de synchronisation séparé de l'entité elle-même | Le plus simple des deux mécanismes qui garantissent qu'un rejeu réseau ne peut jamais créer de doublon ; évite de maintenir une table de correspondance id-opération ↔ id-entité |
| 2026-09-05 | La synchronisation offline-first ne couvre que les ventes et les mouvements de stock manuels, pas encore l'ouverture de table/la prise de commande | Ce sont les deux flux explicitement cités par le prompt maître §25 ; couvrir aussi les tables aurait dépassé un temps raisonnable pour cette phase — l'architecture (dispatch par `entityType`) permet de l'étendre sans refonte |
| 2026-09-05 | Le remboursement volontaire d'un client (`CreditsService.recordRepayment`) est strict (rejette un montant supérieur au solde), contrairement au remboursement automatique et clampé lors de l'annulation d'une vente (`SalesService.refund`) | Deux situations différentes : un client qui rembourse doit voir une erreur si le montant ne correspond pas à un solde réel ; l'annulation d'une vente ne doit jamais échouer pour un désalignement comptable mineur |
| 2026-09-05 | Le type de mouvement de stock `loss` n'est plus accepté sur la route de saisie manuelle depuis la Phase 12 (`in`/`out`/`adjustment` seulement, comme `sale` déjà réservé au flux caisse) — seul `LossesService` peut désormais l'écrire | Avant la Phase 12, une perte saisie manuellement ne laissait qu'un `StockMovement`, sans motif structuré ni valorisation exploitable en comptabilité ; `LossesService` écrit systématiquement le mouvement de stock **et** l'enregistrement `Loss` correspondant dans la même transaction, pour qu'une perte reste toujours traçable financièrement |
| 2026-09-05 | `CashService` crée paresseusement un `PointOfSale`/`CashRegister` par défaut à la première clôture, plutôt que d'exposer un CRUD dédié aux points de vente/caisses | Le schéma (Phase 3) prévoit le multi-point-de-vente, mais aucun établissement n'en a besoin à ce stade et `Sale.pointOfSaleId` lui-même n'est jamais renseigné ailleurs dans le code ; construire une UI multi-caisses maintenant aurait été hors de proportion avec le reste de la Phase 12. Réversible sans changer le contrat de `CashService` le jour où le multi-caisse devient nécessaire |
| 2026-09-05 | Le montant de caisse attendu (`CashService.close`) est calculé comme paiements en espèces moins dépenses de la période, en supposant que toute dépense est payée en espèces depuis la caisse | `Expense` n'a pas de champ méthode de paiement (Phase 3) ; l'hypothèse est raisonnable pour un maquis-bar et documentée plutôt que silencieuse — à revoir si un établissement paie ses dépenses autrement |
| 2026-09-05 | `DecimalTransformInterceptor` (`src/common/`), enregistré globalement dans `main.ts`, convertit tout `Prisma.Decimal` d'une réponse HTTP en nombre JS avant sérialisation | Prisma sérialise `Decimal` en chaîne JSON (`JSON.stringify` appelle son `toJSON()`, qui renvoie une chaîne — confirmé directement), alors que chaque modèle Flutter écrit depuis la Phase 5 analyse les montants avec `(json['x'] as num)`, qui échoue sur une chaîne. Resté invisible pendant 11 phases faute de round-trip HTTP réel (`DATABASE_URL` manquant) ; corrigé une fois pour toutes plutôt que module par module dès qu'il a été repéré en écrivant les tests de la Phase 12 |
| 2026-09-06 | `ReportsService.summary` calcule la marge à partir du `purchasePrice` **actuel** du produit, pas d'un coût figé au moment de la vente | `SaleItem` ne fige que le prix de vente (`unitPrice`), jamais un coût d'achat historique ; ajouter ce champ maintenant, pour une seule phase de reporting, aurait dépassé le périmètre de la Phase 13 — documenté comme approximation plutôt que présenté comme une marge exacte |
| 2026-09-06 | Seul l'export CSV des rapports est livré en Phase 13 ; PDF et Excel (demandés au prompt maître §34) sont reportés | Les deux nécessitent une dépendance de rendu non choisie ni testée, pour une fonctionnalité qui resterait de toute façon invérifiable de bout en bout tant que `DATABASE_URL` manque — mieux vaut un export réellement testé que trois annoncés dont deux jamais exécutés |
| 2026-09-06 | La performance des serveurs (`ReportsService.summary`) s'appuie sur `Sale.createdBy`, pas sur la table `ServerCommission` pourtant prévue au schéma (Phase 3) | `ServerCommission` n'est alimentée par aucun code existant (aucune phase précédente n'y a jamais écrit) ; y baser un rapport aurait affiché des chiffres systématiquement vides plutôt que la performance réelle des ventes |
| 2026-09-06 | Un défaut latent du motif `setState(() { _future = repo.methode(); })` (utilisé par tous les écrans à rechargement depuis la Phase 5) a été découvert et corrigé uniquement dans `ReportsPage` (`future.ignore()`), pas répercuté ailleurs | `flutter_test` répond à toute requête réseau réelle par un faux 400 quasi instantané ; si ce rejet survient avant que `FutureBuilder` ne se réabonne au prochain rebuild, Dart le signale comme non géré — un artefact d'environnement de test (jamais observable en production, où un vrai appel réseau prend toujours assez de temps), qu'aucun test existant sur les autres écrans n'exerçait avant celui-ci |
| 2026-09-06 | Les notifications (Phase 14) sont uniquement in-app (table `notifications`, lues/diffusées via l'API) — aucune notification push (FCM/APNs/Web Push) n'est implémentée | Le schéma (Phase 3) ne modélise aucun jeton d'appareil, et cet environnement n'a ni clé FCM ni configuration Web Push ; construire un flux push sans pouvoir l'exécuter ni le tester aurait été fabriqué plutôt que livré |
| 2026-09-06 | `Notification` est rattachée à `organizationId`, pas à `establishmentId` comme le reste du schéma exposé jusqu'ici ; `NotificationsService.getOrganizationId` traduit et sert aussi de contrôle d'appartenance pour les routes `list`/`unreadCount`/`markAsRead`, volontairement sans `@RequirePermissions` | Ces trois routes doivent rester accessibles à tout membre de l'établissement lisant ses propres notifications, comme `GET /auth/me` ; sans permission dédiée à vérifier, c'est cette fonction — pas le guard — qui empêche un utilisateur non affilié d'accéder aux notifications d'une autre organisation |
| 2026-09-06 | Une notification diffusée (`userId` nul) ne peut pas être marquée lue individuellement — `markAsRead` ne s'applique qu'aux notifications explicitement ciblées sur l'appelant | `readAt` est une colonne unique sur la ligne `Notification`, pas une table de suivi de lecture par utilisateur ; la marquer lue pour une personne la marquerait lue pour toute l'organisation. Limite du schéma documentée plutôt que masquée par une fausse table |
| 2026-09-06 | `NotificationsService.generateLowStockAlerts` est déclenchée à la demande (`POST .../notifications/low-stock-check`), sans ordonnanceur | Aucun cron/scheduler n'est configuré dans cet environnement ; le contrat de la méthode n'a pas besoin de changer le jour où une vraie tâche planifiée existera |
| 2026-09-06 | Le cache hors ligne de la PWA (Phase 15) est un service worker écrit à la main (`web/pwa_cache_worker.js`, cache au fil de l'eau), pas le `flutter_service_worker.js` généré par `flutter build web` | Vérifié directement dans le navigateur : dans ce SDK, le service worker généré par Flutter s'auto-désinstalle à l'activation (`self.registration.unregister()`) — mécanisme officiellement déprécié (flutter/flutter#156910), qui ne fait plus aucune mise en cache. L'hypothèse initiale (« déjà fourni par Flutter ») était fausse ; corrigée avant documentation plutôt que supposée acquise |
| 2026-09-06 | Le nouveau service worker utilise une stratégie de cache « au fil de l'eau » (toute requête même origine réussie est mise en cache après coup), pas une liste de préchargement figée | Flutter ne publie plus de manifeste des fichiers de build depuis la dépréciation de son propre service worker ; `canvaskit/` fait par ailleurs ~37 Mo avec plusieurs variantes selon le navigateur, tout précharger gaspillerait de la bande passante pour des variantes jamais utilisées |
| 2026-09-06 | Le bandeau de mise à jour et le bouton d'installation (Phase 15) sont en JavaScript brut dans `web/index.html`, pas en Dart (`package:web`/`dart:js_interop`) | Du code Dart lié au navigateur aurait dû être importé quelque part dans l'arbre de `main.dart`, que `widget_test.dart` compile et exécute sur la VM (pas Chrome) — un risque réel de casser toute la suite de tests Flutter pour une fonctionnalité qui n'a pas besoin d'être en Dart |

## Points ouverts (nécessitent une décision ou une action ultérieure)

- **Push GitHub** : le remote `origin` (`https://github.com/yasminerestomaquis/Chez_Yasmine.git`) est configuré, mais le compte `gh` authentifié localement (`Autocad-Qgis`) n'a pas les droits de push sur ce dépôt qui appartient au compte `yasminerestomaquis`. À résoudre avant le premier push (ré-authentification `gh auth login` sous le bon compte, jeton d'accès personnel du compte `yasminerestomaquis`, ou ajout d'`Autocad-Qgis` comme collaborateur).
- **Docker / Supabase CLI locaux** : Docker non installé sur cette machine (build de `docker/Dockerfile.nestjs` non testé localement). Supabase CLI utilisable à la demande via `npx supabase@latest` (sans installation globale) mais `supabase start` (stack locale complète) nécessite Docker et n'a pas été utilisé — le développement contre Supabase se fait via les outils MCP (migrations, SQL, Storage).
- **`DATABASE_URL` réel non disponible** : les migrations ont été appliquées via l'API de gestion Supabase (MCP), pas via une connexion Postgres directe. Le mot de passe de connexion (nécessaire pour `prisma db pull`, `prisma migrate dev`, et pour que l'API NestJS tourne réellement) doit être récupéré depuis le dashboard Supabase et renseigné dans `.env`.
- **`npm audit`** : 4 vulnérabilités high résiduelles dans `apps/api/nestjs`, toutes transitives au *CLI* Prisma 7.10.0 (`deepmerge-ts`, `mysql2` via `@prisma/config`) — pas dans le client généré ni le code applicatif. Le correctif automatique rétrograderait vers `prisma@6.19.3` ; accepté pour l'instant, à réévaluer à la prochaine release stable de Prisma.
- **Schéma de base de données** (Phase 3) : conçu et appliqué (voir `docs/database/schema.md`). Reste à faire : brancher Prisma sur une vraie connexion (`DATABASE_URL`), et construire les modules NestJS (services/repositories) qui l'utilisent — pas encore commencé (Phase 5+).
