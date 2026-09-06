# Changelog — Chez Yasmine

## [Unreleased]

### Ajouté
- Structure monorepo v5 (`apps/`, `packages/`, `supabase/`, `docs/*`, `docker/`, `.github/workflows/`).
- Scaffold NestJS (`apps/api/nestjs`), build vérifié.
- Scaffold Flutter Web (`apps/web/flutter`), `flutter analyze`/`flutter test`/`flutter build web` vérifiés.
- SDK Flutter installé localement (`C:\flutter`, clonage du dépôt officiel, branche stable).
- Scaffold Supabase local (`supabase/config.toml`, dossiers `migrations/`, `functions/`, `seed/`).
- Documentation de gouvernance : `CLAUDE.md`, `ARCHITECTURE.md`, `PROJECT_PLAN.md`, `README.md`.
- `.env.example`, `.gitignore`, `Dockerfile.nestjs`, `docker-compose.yml`, workflow CI GitHub Actions (NestJS + Flutter).
- Remote GitHub `origin` configuré vers `https://github.com/yasminerestomaquis/Chez_Yasmine.git` (push encore bloqué, voir `PROJECT_PLAN.md`).
- Branding **Chez Yasmine** : logo top-left dans l'app v1 (prototype) et dans l'app Flutter v5, manifest PWA, favicon, icônes générées depuis `Chez Yasmine.png`.
- Schéma de base de données complet (30 tables) appliqué sur Supabase via 6 migrations versionnées (`supabase/migrations/`), avec RLS multi-tenant sur toutes les tables et advisors sécurité/performance vérifiés (voir `docs/database/schema.md`).
- Seed des rôles/permissions système (`supabase/seed/001_roles_permissions.sql`) : 15 permissions, 8 rôles, 74 associations.
- Prisma 7 intégré dans NestJS (`prisma.config.ts`, `apps/api/nestjs/prisma/schema.prisma`, `PrismaModule`/`PrismaService` via adaptateur `@prisma/adapter-pg`).
- Trigger Postgres `handle_new_user` : auto-crée organisation/établissement/profil/rôle Propriétaire à l'inscription (`supabase/migrations/20260905193641_auth_bootstrap_trigger.sql`).
- Flux Supabase Auth côté Flutter : connexion (mot de passe + OTP e-mail), inscription propriétaire (`apps/web/flutter/lib/auth/`).
- `SupabaseJwtGuard` (vérification JWT via JWKS/ES256), `PermissionsGuard` + `@RequirePermissions`, `AuthorizationService`, `GET /auth/me` (`apps/api/nestjs/src/auth/`).
- `docs/api/auth.md` documentant le flux d'authentification de bout en bout.
- CRUD catégories et produits, bucket Storage `product-images` + RLS, pipeline photo (validation + 4 variantes WebP via `sharp`, upload avec le jeton utilisateur) (`apps/api/nestjs/src/catalog/`, `apps/api/nestjs/src/storage/`).
- UI Flutter catalogue : liste catégories/produits, formulaire produit avec sélecteur photo à 4 options (caméra/galerie/fichier/image générique) (`apps/web/flutter/lib/catalog/`).
- `docs/api/catalog.md` documentant le pipeline produits/photos.
- Mouvements de stock (entrée/sortie/correction/perte), alertes de seuil et historique par produit (`apps/api/nestjs/src/stock/`) ; UI Flutter correspondante (`apps/web/flutter/lib/stock/`).
- `docs/api/stock.md` documentant la logique de stock.
- Vente en caisse (panier, remise, paiement mixte/crédit), décrémentation automatique du stock (mouvement `sale`), remboursement (`apps/api/nestjs/src/pos/`) ; UI Flutter correspondante (`apps/web/flutter/lib/pos/`).
- `docs/api/pos.md` documentant la logique de caisse.
- Plan de salle, additions (ouverture/ajout/retrait d'article/transfert/fusion/division), clôture liée à la caisse (`apps/api/nestjs/src/tables/`) ; UI Flutter correspondante (`apps/web/flutter/lib/tables/`).
- `docs/api/tables.md` documentant la logique tables/additions.
- Idempotence des ventes et mouvements de stock (`id` client réutilisé comme id serveur), moteur de synchronisation par lot (`apps/api/nestjs/src/sync/`) avec vérification de permission par opération.
- File de synchronisation locale, cache catalogue hors ligne, indicateur de connexion (`apps/web/flutter/lib/sync/`, `apps/web/flutter/lib/catalog/catalog_cache.dart`) intégrés à la caisse et au stock.
- `docs/api/sync.md` documentant le mécanisme offline-first.
- Fournisseurs, commandes d'achat, réception avec incrémentation automatique du stock (`apps/api/nestjs/src/purchasing/`) ; UI Flutter correspondante (`apps/web/flutter/lib/purchasing/`).
- `docs/api/purchasing.md` documentant la logique achats/fournisseurs.
- Gestion des clients, historique et remboursement de crédit (`apps/api/nestjs/src/customers/`) ; UI Flutter correspondante (`apps/web/flutter/lib/customers/`).
- Paiement à crédit activé en caisse (sélecteur de client dans `PaymentDialog`), après avoir été volontairement laissé de côté en Phases 7/8.
- `docs/api/customers.md` documentant la logique clients/crédits.
- Dépenses (CRUD), pertes de stock valorisées (`quantity * purchasePrice`, remplace la saisie manuelle de type « perte »), clôture de caisse avec calcul du montant attendu et de l'écart (`apps/api/nestjs/src/{expenses,losses,cash}/`) ; UI Flutter correspondante (`apps/web/flutter/lib/{expenses,losses,cash}/`).
- `DecimalTransformInterceptor` global (`apps/api/nestjs/src/common/`) : corrige la sérialisation des `Decimal` Prisma (chaîne JSON, incompatible avec les modèles Flutter) sur toute réponse de l'API — défaut présent depuis la Phase 5, découvert en Phase 12.
- `docs/api/accounting.md` documentant dépenses/pertes/caisse et la correction de sérialisation.
- Rapports (`apps/api/nestjs/src/reports/`) : chiffre d'affaires, remises, coût des marchandises vendues et marge, dépenses, pertes, bénéfice net estimé, créances clients, alertes de stock bas, produits les plus vendus, performance des serveurs — par jour/semaine/mois/année ou plage explicite, avec export CSV.
- UI Flutter des rapports (`apps/web/flutter/lib/reports/`) : sélecteur de période, indicateurs, top produits, performance serveurs, export CSV.
- `docs/api/reports.md` documentant les indicateurs, les approximations assumées, et l'export CSV-seulement (PDF/Excel reportés).

### Décisions
- Adoption de l'architecture v5 (Flutter + NestJS + Supabase) en remplacement du prototype v1 local (React/Vite/Dexie), conservé comme référence.
- Authentification via Supabase Auth uniquement.
- RLS activée et testée sur toutes les tables comme défense en profondeur, en plus du filtrage applicatif NestJS.
- `@nestjs/mau` désinstallé (non utilisé, source de 5 des 9 vulnérabilités `npm audit` initiales).
- Auto-inscription du propriétaire gérée par un trigger Postgres plutôt qu'un endpoint NestJS ; l'invitation d'utilisateurs supplémentaires est un flux distinct, reporté.
- Upload des photos vers Supabase Storage avec le jeton de l'utilisateur authentifié plutôt qu'une clé `service_role` (RLS Storage suffit, pas de nouveau secret introduit).
- Les pertes de stock ne s'écrivent plus que via le module Pertes (Phase 12), jamais via la saisie manuelle générique, pour garantir une trace comptable systématique.
- Un point de vente/caisse par défaut est créé paresseusement à la première clôture plutôt que d'ajouter un CRUD dédié, en l'absence de besoin multi-caisse actuel.
- Seul l'export CSV des rapports est livré (PDF/Excel reportés, faute de dépendance de rendu choisie/testée).
- La marge des rapports utilise le coût d'achat actuel du produit, faute de coût historique figé sur `SaleItem`.
