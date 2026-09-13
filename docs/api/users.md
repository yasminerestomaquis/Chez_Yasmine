# Utilisateurs — Chez Yasmine

## Routes NestJS

Toutes scopées par établissement, protégées par `SupabaseJwtGuard` + `PermissionsGuard` + `@RequirePermissions('users.manage')` :

```
GET    /establishments/:establishmentId/users                    liste l'équipe (nom, rôle)
GET    /establishments/:establishmentId/roles                    rôles assignables (système + propres à l'organisation)
POST   /establishments/:establishmentId/users/invite              { email, roleId, fullName? } — envoie l'e-mail Supabase
POST   /establishments/:establishmentId/users/invite-link         { email, roleId, fullName? } — renvoie { link }, aucun e-mail envoyé
PATCH  /establishments/:establishmentId/users/:membershipId              { roleId?, fullName? } — deux champs indépendants et optionnels
POST   /establishments/:establishmentId/users/:membershipId/recovery-link  renvoie { link }, aucun e-mail envoyé
DELETE /establishments/:establishmentId/users/:membershipId              retire un membre de l'établissement (ne supprime pas son compte)
```

`:membershipId` est l'id de l'affectation (`UserEstablishmentRole.id`, renvoyé par `GET .../users`), pas l'id de l'utilisateur — un même utilisateur pourrait en théorie avoir plusieurs affectations.

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

## Piège réel : les aperçus de liens (WhatsApp et consorts) consomment le jeton avant le clic (2026-09-09)

Incident réel, confirmé via les journaux Supabase (`query_logs`, source `edge_logs`) : un lien copié via « Copier le lien »/« Réinitialiser le mot de passe » puis transmis à `missakey1@gmail.com` par WhatsApp a été visité **trois fois** en l'espace de 3 minutes — une fois par le user-agent `WhatsApp/2.2634.101`, avant même les deux visites suivantes (navigateur mobile, puis desktop). WhatsApp (comme beaucoup d'apps de messagerie) **visite automatiquement tout lien partagé dans une conversation pour en générer un aperçu** — un simple GET, sans intervention humaine. Or `auth/v1/verify?token=...` de Supabase est un lien à **usage unique** dont la vérification se déclenche sur ce même GET : le robot d'aperçu de WhatsApp consommait donc le jeton avant que la personne ne clique elle-même, qui retombait alors sur l'écran de connexion classique sans jamais comprendre pourquoi (aucun mot de passe à y saisir, puisqu'elle n'en avait jamais défini).

**Correctif** : `generateInviteLink`/`generateRecoveryLink` ne renvoient plus `action_link` (le `/auth/v1/verify?token=...` de Supabase) mais un lien vers l'application elle-même — `${APP_REDIRECT_URL}/?token_hash=<hashed_token>&type=invite|recovery` (`hashed_token`, un autre champ de la réponse `generateLink`, jamais consommé par une simple visite HTML). `LinkConfirmationGate` ([lib/auth/link_confirmation_gate.dart](../../apps/web/flutter/lib/auth/link_confirmation_gate.dart)), enveloppant `AuthGate` dans `main.dart`, lit `token_hash`/`type` sur `Uri.base.queryParameters` au démarrage et appelle lui-même `Supabase.instance.client.auth.verifyOTP(type: ..., tokenHash: ...)` — un robot d'aperçu qui ne charge jamais JavaScript ne déclenche donc plus aucune vérification, seul un vrai navigateur exécutant le code Dart le fait.

**Limite résiduelle assumée** : `inviteUserByEmail` (l'e-mail envoyé directement par Supabase) utilise toujours le modèle d'e-mail par défaut de Supabase avec `{{ .ConfirmationURL }}` (donc `action_link`), non modifiable sans accès au tableau de bord Supabase (Authentication → Email Templates) — un client de messagerie ou un antivirus qui pré-visite les liens (Outlook Safe Links, par exemple) exposerait au même problème. « Copier le lien »/« Réinitialiser le mot de passe » (les chemins construits par ce backend) sont donc les seuls entièrement protégés.

## Retirer un membre / modifier son rôle et son nom (2026-09-09)

`UsersService.removeMember`/`updateMember` réutilisent la même protection anti-élévation que l'invitation (`assertCallerOutranks`, extrait de `assertRoleAssignable`), appliquée cette fois au rôle **actuel** du membre visé : impossible de retirer ou de rétrograder quelqu'un dont le rôle accorde une permission que l'appelant n'a pas lui-même — un Gérant ne peut donc pas retirer ni rétrograder un Propriétaire. `updateMember` valide en plus le **nouveau** rôle de la même façon (double vérification : ancien rôle et nouveau rôle) — mais **uniquement quand `roleId` est fourni** : `updateMember` accepte aussi `fullName` seul (`UserProfile.fullName`, distinct de `UserEstablishmentRole`), sans aucune de ces vérifications ni l'interdiction de se modifier soi-même — changer un nom n'est pas un risque de sécurité, contrairement à changer un rôle.

Trois garde-fous supplémentaires, spécifiques au retrait et au changement de **rôle** (pas au changement de nom) :
- **Impossible de se retirer soi-même** ni de modifier son propre rôle (`BadRequestException`) — évite un verrouillage accidentel. Modifier son propre nom reste en revanche autorisé.
- **Impossible de retirer/rétrograder le dernier membre ayant encore `users.manage`** sur l'établissement (`assertKeepsAtLeastOneUserManager`, `ConflictException`) — sans ce garde-fou, un établissement pourrait se retrouver sans personne capable d'inviter ou de gérer qui que ce soit, un état qui ne serait réparable que manuellement en base.
- `removeMember` ne supprime **que** l'affectation (`UserEstablishmentRole`) — jamais le compte Supabase Auth lui-même, qui peut appartenir à d'autres établissements.

## Réinitialiser le mot de passe d'un membre déjà en place (2026-09-09)

Cas d'usage réel qui a motivé cette fonctionnalité : `missakey1@gmail.com` s'était auto-inscrite avant d'être rattachée (par correction manuelle de données, pas suppression — voir plus bas) à l'établissement réel avec le rôle Gérant. Le Propriétaire ne connaissait pas le mot de passe qu'elle avait choisi à l'inscription.

`SupabaseAdminService.generateRecoveryLink(userId)` — contrairement à `generateInviteLink`, ne crée **aucun** compte (`auth.admin.generateLink({ type: 'recovery', ... })` exige un utilisateur déjà existant) : récupère d'abord l'e-mail via `auth.admin.getUserById` (l'e-mail n'est jamais dupliqué côté Prisma — voir CLAUDE.md), pose `needs_password_setup: true` sur le compte via `auth.admin.updateUserById` (pas dans les métadonnées du lien lui-même, dont le comportement pour `type: 'recovery'` n'est pas garanti — cette étape supplémentaire assure que `SetPasswordPage` s'affichera bien au clic, exactement comme pour une invitation), puis génère le lien. Même principe que `invite-link` : jamais d'e-mail envoyé par le serveur, le lien est copié côté Flutter pour que l'appelant le transmette lui-même.

Même protection anti-élévation que retirer/changer de rôle (`assertCallerOutranks` sur le rôle **actuel** du membre visé) : sans elle, un Gérant pourrait générer un lien pour un Propriétaire, ce qui revient à pouvoir se connecter à sa place jusqu'à ce qu'il change son mot de passe — un lien de réinitialisation vaut en pratique un accès complet et immédiat au compte visé.

## Corriger une affectation existante — pas de suppression de compte (2026-09-09)

Incident réel : `missakey1@gmail.com` s'est auto-inscrite (`signUp` normal, sans passer par une invitation) avant que le module Utilisateurs existe, créant sa propre organisation ("Mon établissement", rôle Propriétaire) au lieu de rejoindre l'établissement réel. L'utilisateur a d'abord demandé la suppression de ce compte — refusée : la suppression permanente d'un compte reste une action que Claude ne doit jamais exécuter, y compris sur demande explicite et répétée (voir les règles de sécurité générales).

Correction effectuée à la place, avec confirmation explicite de l'utilisateur, par modification directe de données (pas de suppression) :
1. `user_profiles.organization_id` de `missakey1` → organisation de l'établissement réel.
2. `user_establishment_roles` existant → `establishment_id`/`role_id` pointés vers l'établissement réel et le rôle Gérant, au lieu de son établissement auto-créé.
3. L'établissement auto-créé, désormais orphelin (vérifié vide : aucun produit, aucun membre restant) → supprimé sur confirmation explicite séparée.
4. `generateRecoveryLink` (ci-dessus) construite ensuite pour que l'utilisateur puisse transmettre à `missakey1` un moyen de définir un nouveau mot de passe, puisque son mot de passe initial (choisi à l'auto-inscription) était inconnu du Propriétaire.

Aucune donnée n'a été supprimée sans confirmation explicite et spécifique à cette suppression précise (distincte de la confirmation donnée pour la correction d'affectation).

## Limite connue : un e-mail déjà enregistré

Si l'adresse a déjà un compte Supabase (propriétaire d'un autre établissement, par exemple), `inviteUserByEmail` échoue — rattacher un utilisateur *existant* à un établissement supplémentaire n'est pas pris en charge (`ConflictException` avec un message clair plutôt qu'un échec silencieux). À construire si le besoin se présente.

## UI Flutter (`lib/users/`)

`UsersPage` : liste de l'équipe (nom, rôle) + bouton "Inviter" ouvrant un dialogue e-mail/nom complet (optionnel)/rôle (menu déroulant des rôles assignables), avec deux actions : **Inviter** (e-mail Supabase) et **Copier le lien** (`invite-link`, copié dans le presse-papiers via `Clipboard.setData`). Chaque ligne de l'équipe porte trois actions — **Réinitialiser le mot de passe** (visible y compris sur sa propre ligne, sans risque particulier), **Modifier le membre** (nom complet + rôle dans un seul dialogue, `_editMember`) et **Retirer** (ces deux dernières masquées sur sa propre ligne, `member.userId == Supabase.instance.client.auth.currentUser?.id`) — en plus du refus serveur déjà en place pour toute tentative malgré tout. `UsersRepository.updateMember` n'envoie que les champs réellement modifiés (comparaison avec la valeur initiale côté UI, avant l'appel). Comme le reste de l'application, l'onglet Utilisateurs n'est pas masqué selon la permission — un refus serveur s'affiche normalement en cas de 403.

## E-mail et statut de connexion (décision actée 2026-09-13)

Demande utilisateur : afficher l'e-mail de chaque membre et voir s'il est actuellement connecté, sinon depuis combien de temps il ne l'est plus.

**E-mail** : `auth.users` n'est pas répliqué dans le schéma Prisma (voir plus haut, « pas de table utilisateurs dupliquée »). `SupabaseAdminService.getEmailsByIds` interroge `auth.admin.getUserById` une fois par membre unique de la liste (en parallèle, `Promise.all`) — une liste d'établissement compte typiquement moins d'une vingtaine de personnes, la pagination de `listUsers()` n'apporterait rien ici.

**Statut « en ligne »** : pas de vrai push temps réel (aucun WebSocket/Supabase Realtime dans ce projet à ce jour — voir CLAUDE.md, « REST (+ WebSocket quand pertinent) », jamais encore jugé pertinent). À la place, `UserProfile.lastSeenAt` (migration `20260913071714_add_user_profile_last_seen_at.sql`) est rafraîchi par `SupabaseJwtGuard.recordLastSeen` sur **chaque requête authentifiée réussie, sur toutes les routes de l'application** — c'est-à-dire dès que la personne utilise concrètement l'app (charger une page, faire une vente, ouvrir un onglet...), pas seulement quand elle se connecte. Throttlé en mémoire à une écriture par minute et par utilisateur (`LAST_SEEN_WRITE_THROTTLE_MS`) pour ne pas ajouter une requête `UPDATE` sur chaque appel API, et **jamais attendu** (`.catch(() => {})` silencieux) : cette écriture annexe ne doit jamais pouvoir faire échouer une authentification par ailleurs valide.

`UsersService.list()` calcule `isOnline = lastSeenAt != null && (maintenant - lastSeenAt) < 2 minutes` (`ONLINE_THRESHOLD_MS`) au moment de la réponse. Ce n'est donc pas un indicateur qui se met à jour tout seul pendant que la liste reste affichée à l'écran — recharger la page (`_reload()`) recalcule un statut à jour. Une personne sans aucune activité depuis plus de 2 minutes bascule "hors ligne", même si son onglet reste ouvert sur un écran statique sans appel réseau — limite assumée d'une approche par activité plutôt que par présence WebSocket réelle, largement suffisante pour ce cas d'usage (savoir qui travaille actuellement, pas une messagerie instantanée).

Côté Flutter (`lib/users/users_page.dart`) : un point de couleur (vert = en ligne, gris = hors ligne) superposé à l'icône de chaque membre, et sous le rôle, soit « En ligne » (vert), soit « Hors ligne · il y a X » (`formatRelativeTime`, `lib/common/formatting.dart` — minutes/heures/jours, jamais vu → « Jamais connecté »).

## Accès retiré au rôle Gérant (décision actée 2026-09-13)

Le Gérant avait `users.manage` par construction (règle générique « tout sauf `roles.manage` », voir `supabase/seed/001_roles_permissions.sql`) — retiré sur demande explicite de l'utilisateur : le module Utilisateurs reste désormais réservé à Super Administrateur/Administrateur/Propriétaire. Deux niveaux, comme partout ailleurs dans l'application :
- **Côté serveur (l'API, pas le rôle "Serveur")** : le seed exclut maintenant `users.manage` de la règle générique du Gérant (`p.code not in ('roles.manage', 'users.manage')`) — un appel à une route `.../users*` par un Gérant renvoie désormais 403. Rejoué en production (idempotent) : la ligne `role_permissions` existante (Gérant, `users.manage`) a été supprimée explicitement, le seed additif (`on conflict do nothing`) n'efface jamais un octroi déjà en place.
- **Client** : contrairement au reste de l'application (dont la règle est de ne jamais masquer un module selon la permission, un refus serveur suffisant), la tuile « Utilisateurs » de la section ADMINISTRATION de l'accueil est ici explicitement masquée pour le Gérant (`HomeDashboard._isGerant`, même section que le module lui-même — vide et donc masquée en entier pour ce rôle) — demande explicite de l'utilisateur (« ne pas voir »), au-delà du simple refus serveur.

Vérifié en base de production : seuls Super Administrateur/Administrateur/Propriétaire portent encore `users.manage`.

## Vérifications effectuées

- `UsersService` : 26 tests (Prisma + `AuthorizationService` + `SupabaseAdminService` mockés) — `invite`/`generateInviteLink` : rôle introuvable, rôle d'une autre organisation, protection anti-élévation, invitation réussie (métadonnées correctes transmises), e-mail déjà enregistré (`ConflictException`), autre erreur Supabase (`BadRequestException`) ; `removeMember`/`updateMember` : membre introuvable, auto-retrait/auto-modification de rôle refusés (mais pas l'auto-modification du nom), protection anti-élévation sur le rôle actuel et le nouveau rôle (jamais appliquée à un changement de nom seul), dernier gestionnaire d'utilisateurs protégé, rôle et nom modifiables indépendamment ou ensemble ; `generateRecoveryLink` : membre introuvable, protection anti-élévation, lien généré pour le bon utilisateur, erreur Supabase traduite ; **`list`** (2 tests, 2026-09-13) : e-mail + `isOnline` ajoutés à chaque membre selon `lastSeenAt`, un seul appel Admin par utilisateur unique même avec plusieurs affectations.
- `SupabaseJwtGuard` : 3 tests supplémentaires (2026-09-13) — `lastSeenAt` écrit pour l'utilisateur authentifié, throttlé en dessous d'une minute pour le même utilisateur, authentification jamais mise en échec même si l'écriture rejette.
- **`generateRecoveryLink` appliquée en conditions réelles** (2026-09-09, sur `missakey1@gmail.com`, après correction de son affectation vers l'établissement réel en rôle Gérant) — voir « Corriger une affectation existante » ci-dessous pour le contexte complet de cet incident.
- `flutter analyze`/`flutter test`/`flutter build web` ✅.
- **Vérifié en conditions réelles** (2026-09-09, compte de démonstration jetable, jamais le compte réel de l'utilisateur) : `POST .../users/invite` atteint bien l'API Supabase (clé `service_role` correctement configurée sur Render) — bloqué uniquement par le quota d'e-mail gratuit de Supabase (`email rate limit exceeded`), confirmant que la seule limite restante est celle documentée ci-dessus, pas un défaut de l'implémentation. Le déclencheur `handle_new_user` a été vérifié directement en base (simulation d'une ligne `auth.users` avec les métadonnées d'invitation) : l'utilisateur simulé a bien été rattaché à l'établissement existant avec le rôle choisi, **sans créer de nouvelle organisation**. Toutes les données de test ont été supprimées après vérification.
- **`SetPasswordPage` vérifiée en conditions réelles** (2026-09-09, compte de démonstration jetable) : connexion avec `needs_password_setup: true` → écran affiché immédiatement à la place de l'application ; mot de passe validé → bascule automatique vers l'application (`onAuthStateChange`, sans navigation manuelle) ; déconnexion puis reconnexion avec le nouveau mot de passe → accès direct à l'application, sans réafficher l'écran. Données de test supprimées après vérification.
- **Correctif du piège des aperçus de liens vérifié en conditions réelles de bout en bout** (2026-09-10, compte de démonstration jetable, API déployée sur Render + application déployée sur Vercel) : lien généré via `POST .../users/invite-link` (confirmé au format `.../?token_hash=...&type=invite`, plus de `action_link` Supabase brut) ; une requête GET passive avec l'en-tête `User-Agent: WhatsApp/2.2634.101` (simulant l'aperçu automatique) exécutée en premier via `curl` — confirmée sans effet, puisqu'elle ne fait qu'atteindre l'application statique sur Vercel, sans jamais appeler `verifyOTP` (chargement de JavaScript requis) ; le clic réel effectué ensuite dans un navigateur a bien affiché `SetPasswordPage`, permis de définir un mot de passe, puis basculé automatiquement vers l'application. Vérifié en base que l'utilisateur invité a bien rejoint le même établissement que l'inviteur avec le rôle Gérant (aucune organisation fantôme) et que `needs_password_setup` est bien repassé à `false`. Toutes les données de test (2 comptes, 1 organisation, 1 établissement) supprimées après vérification, confirmé par un comptage à 0.
- **Non vérifié en conditions réelles** : la réception effective d'un e-mail (chemin `POST .../users/invite`, `inviteUserByEmail`) par une vraie boîte de réception — reste par ailleurs le seul chemin encore exposé au piège des aperçus de liens, son gabarit d'e-mail Supabase n'étant pas modifiable sans accès au tableau de bord (voir ci-dessus).
