# CLAUDE.md — Chez Yasmine (MaquisBar)

Référentiel permanent des règles du projet. À maintenir à jour à chaque évolution d'architecture.

Document de référence métier : `PROMPT/Prompt maître Claude Code — MaquisBar PWA — Version consolidée v5.md` (ci-après « le prompt maître »).

## Nom du produit

- Application : **Chez Yasmine**
- Codebase / dépôt interne : `MaquisBar` (nom de code technique conservé dans le code, les schémas de base de données et les identifiants internes — n'affecte pas la marque visible)
- Logo : `Chez Yasmine.png` (racine du dépôt), décliné en icônes PWA sous `apps/web/flutter/web/icons/`

## Architecture

```
Flutter Web (PWA)  →  HTTPS/REST + WebSocket  →  NestJS API  →  Supabase (PostgreSQL, Storage, Auth)
```

- Le client (Flutter) n'est jamais une source de confiance : toute opération métier critique (vente, paiement, remboursement, mouvement de stock, perte, clôture de caisse, crédit) passe par NestJS.
- Supabase fournit PostgreSQL, le Storage (photos), l'authentification et RLS. NestJS applique les règles métier, la validation et le RBAC applicatif par-dessus RLS (défense en profondeur, pas RLS seule).
- Multi-tenant : `Organization → Establishment → PointOfSale`. Toute donnée métier est rattachée à une organisation ; l'isolation est garantie à la fois par NestJS (filtrage systématique par `organization_id`) et par RLS Postgres.

## Stack

| Couche | Choix |
|---|---|
| Front-end | Flutter (Web target), PWA (manifest + service worker Flutter) |
| Back-end | NestJS + TypeScript, REST (+ WebSocket quand pertinent) |
| Données | Supabase (PostgreSQL 17), Prisma comme ORM côté NestJS |
| Auth | **Supabase Auth** (email/mot de passe, OTP). NestJS vérifie le JWT Supabase (JWKS) ; pas de table utilisateurs/mots de passe dupliquée côté NestJS. RBAC applicatif (rôles/permissions) stocké et appliqué par NestJS + RLS. |
| Infra | GitHub + GitHub Actions, Docker |

### Décision actée : authentification

Validée explicitement par l'utilisateur (2026-09-05) : Supabase Auth est le fournisseur d'identité unique, pour éviter une double authentification Supabase/NestJS. Voir `docs/decisions/`.

## Projet Supabase

- Organisation : `yasminerestomaquis's Org` (`coxrsjpqafoeqqjtxbhz`)
- Projet : `yasminerestomaquis's Project` (`tsebsulvhgttdwtgqfoj`), région `eu-west-1`, Postgres 17
- URL API : `https://tsebsulvhgttdwtgqfoj.supabase.co`
- Aucune table/migration au démarrage du projet v5 (état vierge au 2026-09-05).
- Toute modification de schéma passe par une migration versionnée dans `supabase/migrations/` (jamais de modification manuelle de la structure en production).

## Dépôt GitHub

- Distant : `https://github.com/yasminerestomaquis/Chez_Yasmine.git` (`origin`)
- ⚠️ Le compte GitHub authentifié localement (`gh auth status`) n'a pas les droits de push sur ce dépôt à ce jour — voir `PROJECT_PLAN.md` / problèmes connus.

## Conventions Git

- Branches : `main` (ou `master` en local tant que le remote n'est pas synchronisé), `develop`, `feature/*`, `fix/*`, `hotfix/*`.
- Commits : préfixes `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`.
- Ne jamais committer `.env`, `.env.production`, secrets, tokens, clés privées. Utiliser `.env.example`.
- Ne jamais `git push`, supprimer une branche, réécrire l'historique, force-push, ou exécuter une migration destructive en production sans confirmation explicite de l'utilisateur.

## Conventions de code

- TypeScript strict côté NestJS et packages partagés (`packages/types`, `packages/shared`).
- Logique métier pure (calculs de caisse, stock, crédit, rapports) isolée dans des services/fonctions testables sans dépendance HTTP/DB directe.
- Pas d'abstraction prématurée : ne pas généraliser avant qu'un second cas d'usage concret existe.
- Pas de `try/catch` qui masque une erreur ; pas de désactivation de contrôle de sécurité pour "faire fonctionner" temporairement une fonctionnalité.

## Règles Supabase / PostgreSQL

- UUID pour tous les identifiants.
- RLS activé sur toutes les tables métier ; policies écrites et testées avant mise en production.
- Migrations versionnées uniquement (`supabase/migrations/`), jamais de modification manuelle en prod.
- Le rôle `service_role` (clé secrète) ne doit jamais être exposé côté client ; il n'est utilisé que côté NestJS/serveur.

## Règles de gestion des images

- Upload : caméra, galerie, fichier, ou image générique par défaut — disponible pour toute catégorie de produit.
- Stockage Supabase Storage, chemin `product-images/{organization_id}/{establishment_id}/{product_id}/{uuid}.webp`. PostgreSQL ne stocke que les métadonnées.
- Pipeline : validation (MIME, taille, dimensions) → compression → redimensionnement → conversion WebP si pertinent → génération thumbnail/small/medium/large → upload. Fichiers renommés en UUID, jamais le nom fourni par l'utilisateur.
- La caisse et le catalogue utilisent les variantes optimisées (thumbnail/small), jamais l'image originale.
- Cache local (Service Worker / IndexedDB côté Flutter Web) pour un catalogue exploitable hors ligne.

## Règles PWA / offline-first

- Flutter Web configuré comme PWA installable (manifest, service worker, icônes, splash screen).
- Fonctionnement hors ligne obligatoire pour : consultation catalogue (avec photos en cache), ouverture de table, prise de commande, vente, paiement, opérations de stock autorisées.
- Les opérations réalisées hors ligne sont mises en file locale puis synchronisées ; aucune donnée n'est perdue en cas de coupure réseau.

## Règles de synchronisation

- Chaque opération de synchronisation porte : `id, operation_type, entity_type, entity_id, payload, user_id, device_id, created_at, status, attempt_count`.
- Statuts : `PENDING → SYNCING → SYNCED / FAILED / CONFLICT`.
- Opérations critiques (vente, paiement, mouvement de stock, clôture) **idempotentes** via identifiant unique d'opération — jamais de duplication en cas de renvoi.
- Conflits sur données financières/stock : jamais de simple "dernier écrit gagne". Détection, journalisation, présentation et résolution selon règle métier documentée.

## Règles de sécurité

- HTTPS partout, validation systématique des entrées, RBAC + RLS, rate limiting, protection brute-force.
- Toute opération sensible est auditable (`AuditLog`).
- Secrets uniquement via variables d'environnement / secrets CI, jamais en dur ni committés.

## Règles de tests

- Unitaires : logique métier pure (caisse, stock, crédit, permissions).
- Intégration : API NestJS, Postgres/Supabase, Storage, authentification.
- E2E : parcours complet (connexion → produit → photo → vente → paiement → stock → clôture) et parcours offline→sync (vente hors ligne → retour réseau → synchronisation → absence de doublon).
- Aucune fonctionnalité n'est "terminée" sans compiler, passer ses tests critiques, et être documentée.

## Procédure de déploiement (cible)

1. CI GitHub Actions sur chaque PR : lint → tests → analyse → build.
2. Sur la branche de production : tests → build API → build Flutter Web (PWA) → déploiement.
3. Secrets exclusivement via les secrets GitHub Actions / variables d'environnement de la plateforme d'hébergement.
4. Migrations Supabase appliquées avant le déploiement applicatif, jamais après.

## État des lieux — legacy v1

Un premier prototype (React + TypeScript + Vite + Dexie/IndexedDB, mono-établissement, 100% local, sans backend) a été développé le 2026-07-25 dans `docs/superpowers/specs/2026-07-25-maquisbar-pwa-design.md` et `docs/superpowers/plans/2026-07-25-maquisbar-pwa-implementation.md`, avec une implémentation fonctionnelle dans le worktree `.claude/worktrees/maquisbar-v1` (branche `worktree-maquisbar-v1`, ~101 tests passants : caisse, tables/additions, paiements, stock).

**Ce prototype est superseded par l'architecture v5 ci-dessus** (décision utilisateur du 2026-09-05 : « Considère le V5 »). Il n'est ni supprimé ni migré automatiquement — il reste disponible comme référence pour les règles métier déjà validées (totaux de panier, ventilation de paiement, mouvements de stock, plafonds de crédit, agrégats de rapport), qui peuvent inspirer l'implémentation NestJS équivalente. Ne pas repartir de ce code pour le produit final sans décision explicite contraire.
