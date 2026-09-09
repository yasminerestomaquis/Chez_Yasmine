# Utilisateurs — Chez Yasmine

## Routes NestJS

Toutes scopées par établissement, protégées par `SupabaseJwtGuard` + `PermissionsGuard` + `@RequirePermissions('users.manage')` :

```
GET  /establishments/:establishmentId/users              liste l'équipe (nom, rôle)
GET  /establishments/:establishmentId/roles              rôles assignables (système + propres à l'organisation)
POST /establishments/:establishmentId/users/invite       { email, roleId, fullName? } — envoie l'e-mail Supabase
POST /establishments/:establishmentId/users/invite-link  { email, roleId, fullName? } — renvoie { link }, aucun e-mail envoyé
```

## Pourquoi une invitation, pas une simple création de compte

`docs/api/auth.md` documentait ce point comme ouvert : l'auto-inscription (`supabase.auth.signUp`) crée systématiquement une **nouvelle** organisation via le trigger `handle_new_user` — adaptée au propriétaire qui s'inscrit seul, pas à l'ajout d'un coéquipier dans un établissement existant. Claude ne crée jamais de compte ni ne manipule de mot de passe pour un tiers ; la seule action légitime est de déclencher **l'invitation officielle Supabase Auth** (`auth.admin.inviteUserByEmail`), qui envoie un e-mail avec un lien où la personne invitée choisit elle-même son mot de passe.

## `SupabaseAdminService` — seul point d'usage de la clé `service_role`

`apps/api/nestjs/src/auth/supabase-admin.service.ts` instancie un client Supabase avec `SUPABASE_SERVICE_ROLE_KEY` (jamais exposée au client — CLAUDE.md) : `auth.admin.inviteUserByEmail` n'est accessible qu'avec cette clé, contrairement au reste de l'application qui utilise systématiquement le jeton de l'utilisateur authentifié (`SupabaseStorageService`). **Nécessite une variable d'environnement supplémentaire sur Render** (`SUPABASE_SERVICE_ROLE_KEY`, valeur dans le tableau de bord Supabase → Project Settings → API → clé secrète `service_role`) — sans elle, `POST .../users/invite` échoue avec une erreur claire plutôt qu'un comportement silencieux.

## Éviter l'organisation fantôme : `invited_establishment_id`/`invited_role_id`

`UsersService.invite` passe `{ invited_establishment_id, invited_role_id, full_name }` dans les métadonnées de l'invitation (`raw_user_meta_data` sur la ligne `auth.users` créée). La migration `20260909120000_admin_invite_bootstrap.sql` modifie `handle_new_user` pour détecter ces métadonnées : si présentes, le trigger rattache directement l'utilisateur à l'établissement/rôle choisis **sans créer de nouvelle organisation** ; sinon (auto-inscription normale), le comportement d'origine (nouvelle organisation + rôle Propriétaire) est inchangé.

## Protection anti-élévation de privilèges

`UsersService.invite` compare les permissions du rôle à affecter à celles de l'appelant (`AuthorizationService.getPermissionCodes`) : **impossible d'affecter un rôle qui accorde une permission que l'appelant n'a pas lui-même** sur cet établissement (`ForbiddenException` sinon). Ainsi un Gérant (qui a `users.manage` mais pas `roles.manage`) ne peut pas inviter quelqu'un avec le rôle Propriétaire, puisque Propriétaire accorde `roles.manage` que le Gérant n'a pas — sans avoir à coder un cas spécial par nom de rôle, la règle est générique et fonctionne aussi pour de futurs rôles personnalisés.

## Alternative sans e-mail : `invite-link` (2026-09-09)

Le service d'e-mail gratuit et partagé de Supabase a un quota très bas (`email rate limit exceeded`, rencontré en conditions réelles lors de la vérification de cette fonctionnalité) — bloquant tant qu'un SMTP personnalisé n'est pas configuré (Supabase → Authentication → Emails → SMTP Settings). `SupabaseAdminService.generateInviteLink` utilise `auth.admin.generateLink({ type: 'invite', ... })` : crée le compte exactement comme `inviteUserByEmail` (mêmes métadonnées, même déclencheur) mais **ne passe jamais par le mailer de Supabase** — il renvoie directement le lien. `UsersService.generateInviteLink` réutilise la même validation (`assertRoleAssignable`, factorisée entre les deux méthodes) et la même traduction d'erreur que `invite`.

Le lien est copié dans le presse-papiers côté Flutter (`Clipboard.setData`) — **jamais envoyé par le serveur à la place de l'appelant** : c'est le Propriétaire/Gérant qui le transmet lui-même par le canal de son choix (WhatsApp, SMS, son propre e-mail...), cohérent avec le principe que Claude ne crée ni n'envoie jamais un compte/message à un tiers en autonomie.

## Après le clic sur le lien : `needs_password_setup` et `SetPasswordPage`

Un lien d'invitation (envoyé par e-mail ou copié) connecte directement la personne à l'application — c'est le fonctionnement standard des liens magiques Supabase — mais elle n'a encore jamais choisi de mot de passe : sans rien de plus, elle n'aurait aucun moyen de se reconnecter une fois cette première session expirée.

`UsersService.inviteMetadata` pose `needs_password_setup: true` dans les métadonnées de l'invitation (en plus de `invited_establishment_id`/`invited_role_id`, ci-dessus). `AuthGate` ([lib/auth/auth_gate.dart](../../apps/web/flutter/lib/auth/auth_gate.dart)) le lit sur `currentUser.userMetadata` : tant que ce drapeau vaut `true`, il affiche `SetPasswordPage` ([lib/auth/set_password_page.dart](../../apps/web/flutter/lib/auth/set_password_page.dart)) à la place de l'application. Ce formulaire (mot de passe + confirmation, 6 caractères minimum, même règle que `SignUpPage`) appelle `Supabase.instance.client.auth.updateUser(UserAttributes(password: ..., data: {'needs_password_setup': false}))` — l'événement `onAuthStateChange` qui en résulte fait automatiquement réévaluer `AuthGate`, qui bascule alors vers l'application normale, sans navigation manuelle à coder.

Fonctionne à l'identique pour les deux chemins d'invitation (e-mail et lien copié), puisque les deux passent par la même méthode `inviteMetadata`. N'affecte jamais l'auto-inscription normale (`SignUpPage`), qui ne pose pas ce drapeau.

## Limite connue : un e-mail déjà enregistré

Si l'adresse a déjà un compte Supabase (propriétaire d'un autre établissement, par exemple), `inviteUserByEmail` échoue — rattacher un utilisateur *existant* à un établissement supplémentaire n'est pas pris en charge (`ConflictException` avec un message clair plutôt qu'un échec silencieux). À construire si le besoin se présente.

## UI Flutter (`lib/users/`)

`UsersPage` : liste de l'équipe (nom, rôle) + bouton "Inviter" ouvrant un dialogue e-mail/nom complet (optionnel)/rôle (menu déroulant des rôles assignables), avec deux actions : **Inviter** (e-mail Supabase) et **Copier le lien** (`invite-link`, copié dans le presse-papiers via `Clipboard.setData`). Comme le reste de l'application, l'onglet Utilisateurs n'est pas masqué selon la permission — un refus serveur s'affiche normalement en cas de 403.

## Vérifications effectuées

- `UsersService.invite`/`generateInviteLink` : 9 tests (Prisma + `AuthorizationService` + `SupabaseAdminService` mockés) — rôle introuvable, rôle d'une autre organisation, protection anti-élévation (bloque/autorise selon les permissions, y compris réutilisée par `generateInviteLink`), invitation réussie (métadonnées correctes transmises), e-mail déjà enregistré (`ConflictException`), autre erreur Supabase (`BadRequestException`), `generateInviteLink` n'appelle jamais le chemin d'envoi d'e-mail.
- `flutter analyze`/`flutter test`/`flutter build web` ✅.
- **Vérifié en conditions réelles** (2026-09-09, compte de démonstration jetable, jamais le compte réel de l'utilisateur) : `POST .../users/invite` atteint bien l'API Supabase (clé `service_role` correctement configurée sur Render) — bloqué uniquement par le quota d'e-mail gratuit de Supabase (`email rate limit exceeded`), confirmant que la seule limite restante est celle documentée ci-dessus, pas un défaut de l'implémentation. Le déclencheur `handle_new_user` a été vérifié directement en base (simulation d'une ligne `auth.users` avec les métadonnées d'invitation) : l'utilisateur simulé a bien été rattaché à l'établissement existant avec le rôle choisi, **sans créer de nouvelle organisation**. Toutes les données de test ont été supprimées après vérification.
- **`SetPasswordPage` vérifiée en conditions réelles** (2026-09-09, compte de démonstration jetable) : connexion avec `needs_password_setup: true` → écran affiché immédiatement à la place de l'application ; mot de passe validé → bascule automatique vers l'application (`onAuthStateChange`, sans navigation manuelle) ; déconnexion puis reconnexion avec le nouveau mot de passe → accès direct à l'application, sans réafficher l'écran. Données de test supprimées après vérification.
- **Non vérifié en conditions réelles** : `POST .../users/invite-link` et la réception effective d'un e-mail/lien par une vraie boîte de réception.
