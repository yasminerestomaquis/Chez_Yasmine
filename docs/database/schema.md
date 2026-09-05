# Schéma de base de données — Chez Yasmine

Appliqué sur le projet Supabase `tsebsulvhgttdwtgqfoj` (eu-west-1, Postgres 17) via les migrations dans `supabase/migrations/`. Miroir exact dans `apps/api/nestjs/prisma/schema.prisma` (écrit à la main, aucune introspection possible sans les identifiants réels de la base — à revalider avec `prisma db pull` une fois `DATABASE_URL` renseigné).

## Migrations appliquées

| Version | Nom | Contenu |
|---|---|---|
| 20260905191441 | core_schema | Les 30 tables du modèle (§16 du prompt maître) : tenancy, RBAC, catalogue, stock, achats, tables/service, clients/crédit, ventes/POS, dépenses/pertes/caisse/comptabilité, notifications/abonnement/synchronisation/audit |
| 20260905191510 | rls_policies | RLS sur toutes les tables + fonctions utilitaires `current_user_organization_id()` / `user_has_establishment_access()` |
| 20260905191544 | restrict_rls_helper_functions | Retire l'exécution publique par défaut (PUBLIC) des fonctions RLS |
| 20260905191620 | revoke_rls_helper_functions_from_anon | Retire explicitement le droit d'exécution accordé par défaut au rôle `anon` |
| 20260905191701 | add_missing_foreign_key_indexes | Index manquants relevés par l'advisor de performance Supabase |
| 20260905191800 | add_system_role_unique_index | Index unique partiel sur `roles(name) where organization_id is null`, pour que le seed des rôles système soit idempotent |
| 20260905193000 | auth_bootstrap_trigger | Trigger `on_auth_user_created` (SECURITY DEFINER) sur `auth.users` : à l'inscription, crée automatiquement l'organisation, l'établissement, le `user_profiles` et affecte le rôle système « Propriétaire ». Voir `docs/api/auth.md`. |

Seed (hors migrations, rejouable) : `supabase/seed/001_roles_permissions.sql` — 15 permissions, 8 rôles système (Super Administrateur, Administrateur, Propriétaire, Gérant, Caissier, Serveur, Magasinier, Comptable), 74 associations rôle/permission. Déjà exécuté sur le projet.

## Isolation multi-tenant (RLS)

- `organizations`, `establishments`, `user_profiles`, `notifications`, `subscriptions` : policy directe sur `organization_id`.
- Tables portant `establishment_id` (produits, catégories, fournisseurs, achats, tables, commandes, ventes, clients, dépenses, pertes, etc.) : policy via `user_has_establishment_access(establishment_id)`.
- Tables filles sans `establishment_id` direct (images produit, mouvements de stock, lignes de commande/vente, paiements, crédits, clôtures de caisse, commissions...) : policy via `EXISTS` en remontant à la table parente.
- `sync_operations` et `audit_logs` : RLS activé, **aucune policy** pour `authenticated`/`anon` — accessibles uniquement via `service_role` (NestJS), qui contourne RLS. C'est intentionnel : ce sont des journaux internes.
- `service_role` (utilisé exclusivement côté NestJS, jamais exposé au client) contourne RLS via son attribut `BYPASSRLS`. Les policies ci-dessus protègent la clé `anon`/`authenticated`, en défense en profondeur — le chemin métier normal passe toujours par NestJS (cf. CLAUDE.md, règle §5 du prompt maître).

## Finding de sécurité accepté

L'advisor Supabase signale que `current_user_organization_id()` et `user_has_establishment_access()` restent appelables directement en RPC par le rôle `authenticated` (`/rest/v1/rpc/...`). C'est nécessaire : les policies RLS elles-mêmes s'exécutent avec les droits du rôle appelant et ont donc besoin de ce droit d'exécution pour fonctionner. Ce n'est pas une fuite de données : ces fonctions ne renvoient que l'organisation de l'appelant lui-même ou un booléen, jamais les données d'un autre tenant. Le droit a en revanche été retiré au rôle `anon` (aucune policy ne l'utilise pour ce rôle).

## Prisma (NestJS)

Prisma 7 a supprimé `datasource.url` du fichier `schema.prisma` : la chaîne de connexion vit dans `prisma.config.ts` (lu par le CLI pour les migrations/introspection) et le `PrismaClient` applicatif est construit avec un adaptateur pilote (`@prisma/adapter-pg`) dans `src/prisma/prisma.service.ts`. Voir ce fichier pour l'intégration NestJS (module global `PrismaModule`).

Les colonnes `status`/`type`/`method`/`source` sont stockées en `text` avec contrainte `CHECK` côté Postgres (pas d'enum natif), et donc modélisées en `String` côté Prisma pour rester fidèles à la base réelle.

## Point ouvert

Aucune valeur réelle de `DATABASE_URL` (mot de passe de connexion directe Postgres) n'est disponible dans cet environnement — seul l'accès MCP Supabase (API de gestion) a été utilisé pour appliquer les migrations. `prisma db pull`/`prisma migrate` depuis la machine de développement, et toute connexion directe de NestJS à la base, nécessitent de renseigner ce mot de passe dans `.env` (récupérable depuis le dashboard Supabase du projet `tsebsulvhgttdwtgqfoj`).
