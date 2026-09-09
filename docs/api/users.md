# Utilisateurs — Chez Yasmine

## Routes NestJS

Toutes scopées par établissement, protégées par `SupabaseJwtGuard` + `PermissionsGuard` + `@RequirePermissions('users.manage')` :

```
GET  /establishments/:establishmentId/users          liste l'équipe (nom, rôle)
GET  /establishments/:establishmentId/roles          rôles assignables (système + propres à l'organisation)
POST /establishments/:establishmentId/users/invite    { email, roleId, fullName? }
```

## Pourquoi une invitation, pas une simple création de compte

`docs/api/auth.md` documentait ce point comme ouvert : l'auto-inscription (`supabase.auth.signUp`) crée systématiquement une **nouvelle** organisation via le trigger `handle_new_user` — adaptée au propriétaire qui s'inscrit seul, pas à l'ajout d'un coéquipier dans un établissement existant. Claude ne crée jamais de compte ni ne manipule de mot de passe pour un tiers ; la seule action légitime est de déclencher **l'invitation officielle Supabase Auth** (`auth.admin.inviteUserByEmail`), qui envoie un e-mail avec un lien où la personne invitée choisit elle-même son mot de passe.

## `SupabaseAdminService` — seul point d'usage de la clé `service_role`

`apps/api/nestjs/src/auth/supabase-admin.service.ts` instancie un client Supabase avec `SUPABASE_SERVICE_ROLE_KEY` (jamais exposée au client — CLAUDE.md) : `auth.admin.inviteUserByEmail` n'est accessible qu'avec cette clé, contrairement au reste de l'application qui utilise systématiquement le jeton de l'utilisateur authentifié (`SupabaseStorageService`). **Nécessite une variable d'environnement supplémentaire sur Render** (`SUPABASE_SERVICE_ROLE_KEY`, valeur dans le tableau de bord Supabase → Project Settings → API → clé secrète `service_role`) — sans elle, `POST .../users/invite` échoue avec une erreur claire plutôt qu'un comportement silencieux.

## Éviter l'organisation fantôme : `invited_establishment_id`/`invited_role_id`

`UsersService.invite` passe `{ invited_establishment_id, invited_role_id, full_name }` dans les métadonnées de l'invitation (`raw_user_meta_data` sur la ligne `auth.users` créée). La migration `20260909120000_admin_invite_bootstrap.sql` modifie `handle_new_user` pour détecter ces métadonnées : si présentes, le trigger rattache directement l'utilisateur à l'établissement/rôle choisis **sans créer de nouvelle organisation** ; sinon (auto-inscription normale), le comportement d'origine (nouvelle organisation + rôle Propriétaire) est inchangé.

## Protection anti-élévation de privilèges

`UsersService.invite` compare les permissions du rôle à affecter à celles de l'appelant (`AuthorizationService.getPermissionCodes`) : **impossible d'affecter un rôle qui accorde une permission que l'appelant n'a pas lui-même** sur cet établissement (`ForbiddenException` sinon). Ainsi un Gérant (qui a `users.manage` mais pas `roles.manage`) ne peut pas inviter quelqu'un avec le rôle Propriétaire, puisque Propriétaire accorde `roles.manage` que le Gérant n'a pas — sans avoir à coder un cas spécial par nom de rôle, la règle est générique et fonctionne aussi pour de futurs rôles personnalisés.

## Limite connue : un e-mail déjà enregistré

Si l'adresse a déjà un compte Supabase (propriétaire d'un autre établissement, par exemple), `inviteUserByEmail` échoue — rattacher un utilisateur *existant* à un établissement supplémentaire n'est pas pris en charge (`ConflictException` avec un message clair plutôt qu'un échec silencieux). À construire si le besoin se présente.

## UI Flutter (`lib/users/`)

`UsersPage` : liste de l'équipe (nom, rôle) + bouton "Inviter" (icône `person_add_alt_outlined`) ouvrant un dialogue e-mail/nom complet (optionnel)/rôle (menu déroulant des rôles assignables). Comme le reste de l'application, l'onglet Utilisateurs n'est pas masqué selon la permission — un refus serveur s'affiche normalement en cas de 403.

## Vérifications effectuées

- `UsersService.invite` : 6 tests (Prisma + `AuthorizationService` + `SupabaseAdminService` mockés) — rôle introuvable, rôle d'une autre organisation, protection anti-élévation (bloque/autorise selon les permissions), invitation réussie (métadonnées correctes transmises), e-mail déjà enregistré (`ConflictException`), autre erreur Supabase (`BadRequestException`).
- `flutter analyze`/`flutter test`/`flutter build web` ✅.
- **Non vérifié en conditions réelles** : un envoi effectif d'invitation (bloqué par l'absence de `SUPABASE_SERVICE_ROLE_KEY` sur Render, à renseigner par l'utilisateur — pas d'accès à ce tableau de bord) et par la limite d'envoi d'e-mails Supabase déjà atteinte plus tôt dans le projet.
