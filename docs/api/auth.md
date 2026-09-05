# Authentification et autorisation — Chez Yasmine

## Principe

L'authentification est entièrement déléguée à **Supabase Auth**. NestJS n'émet ni ne stocke aucun mot de passe ; il se contente de vérifier les JWT émis par Supabase et d'appliquer le RBAC métier par-dessus.

```
Flutter ──(email/mdp ou OTP)──> Supabase Auth ──(JWT ES256)──> Flutter
Flutter ──(Authorization: Bearer <jwt>)──> NestJS ──(vérifie via JWKS)──> route protégée
```

## Inscription (bootstrap propriétaire)

`supabase.auth.signUp(email, password, data: { organization_name, full_name })` côté Flutter ([lib/auth/sign_up_page.dart](../../apps/web/flutter/lib/auth/sign_up_page.dart)) déclenche le trigger Postgres `handle_new_user` (`supabase/migrations/20260905193641_auth_bootstrap_trigger.sql`), exécuté en `SECURITY DEFINER` (contourne RLS car l'utilisateur n'a par définition pas encore d'organisation) :

1. crée une `Organization` et un `Establishment` nommés d'après `organization_name` ;
2. crée le `user_profiles` correspondant ;
3. affecte le rôle système **Propriétaire** (toutes permissions) sur cet établissement.

Portée volontairement limitée à l'auto-inscription du propriétaire (cas d'usage MVP mono-établissement). Inviter un utilisateur supplémentaire dans une organisation existante est un flux distinct, non traité ici — à construire côté NestJS (`service_role`) en Phase 4.1/5.

Vérifié en conditions réelles le 2026-09-05 (compte de test créé puis supprimé) : organisation, établissement, profil et rôle Propriétaire correctement créés par le trigger.

## Connexion

Deux méthodes, toutes deux gérées entièrement par Supabase Auth :

- **Mot de passe** : `signInWithPassword` ([lib/auth/login_page.dart](../../apps/web/flutter/lib/auth/login_page.dart)).
- **OTP par e-mail** : `signInWithOtp` puis `verifyOTP` ([lib/auth/otp_verify_page.dart](../../apps/web/flutter/lib/auth/otp_verify_page.dart)).

`AuthGate` ([lib/auth/auth_gate.dart](../../apps/web/flutter/lib/auth/auth_gate.dart)) écoute `Supabase.instance.client.auth.onAuthStateChange` et bascule automatiquement entre écran de connexion et application.

## Vérification côté NestJS

Le projet Supabase signe ses JWT en **ES256 via JWKS** (`GET /auth/v1/.well-known/jwks.json`), pas avec un secret partagé HS256 — confirmé en interrogeant l'endpoint réel. `SupabaseJwtGuard` ([src/auth/supabase-jwt.guard.ts](../../apps/api/nestjs/src/auth/supabase-jwt.guard.ts)) :

1. extrait le `Bearer <jwt>` de l'en-tête `Authorization` ;
2. le vérifie via `jose.jwtVerify` contre le JWKS distant (mis en cache), avec `issuer = "<SUPABASE_URL>/auth/v1"` et `audience = "authenticated"` ;
3. attache le payload décodé (`sub`, `email`, `user_metadata`, ...) à `request.user`.

Vérifié en conditions réelles : un jeton émis par une vraie connexion Supabase est accepté (payload décodé correct), un jeton altéré est rejeté (`signature verification failed`). Tests unitaires (mock de `jose`) dans `supabase-jwt.guard.spec.ts`.

Usage :

```ts
@UseGuards(SupabaseJwtGuard)
@Get('quelque-chose')
handler(@CurrentUser() user: SupabaseUser) { ... }
```

## Permissions (RBAC)

`PermissionsGuard` + `@RequirePermissions('code.permission')` ([src/auth/permissions.guard.ts](../../apps/api/nestjs/src/auth/permissions.guard.ts)) vérifient, via `AuthorizationService` (Prisma), que l'utilisateur authentifié a bien l'une des permissions du catalogue (`supabase/seed/001_roles_permissions.sql`) sur l'établissement identifié par le paramètre de route **`:establishmentId`** — convention à respecter pour toute route protégée par ce guard.

```ts
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('settings.manage')
@Get('establishments/:establishmentId/...')
handler() { ... }
```

`PermissionsGuard` doit toujours être combiné avec `SupabaseJwtGuard` (qui peuple `request.user` en premier).

## Point ouvert

`AuthController.me()` (`GET /auth/me`) et `PermissionsGuard` interrogent la base via Prisma — non testés en conditions réelles faute de `DATABASE_URL` avec un mot de passe valide dans cet environnement (voir `PROJECT_PLAN.md`). Seule la vérification du JWT (sans accès base) a pu être validée en conditions réelles.
