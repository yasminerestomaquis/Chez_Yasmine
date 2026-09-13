# Notifications — Chez Yasmine

## Routes

```
GET    /establishments/:establishmentId/notifications                 (authentifié, pas de permission dédiée)
GET    /establishments/:establishmentId/notifications/unread-count    (authentifié)
PATCH  /establishments/:establishmentId/notifications/:id/read        (authentifié)
POST   /establishments/:establishmentId/notifications/broadcast       (authentifié — voir « Diffusion » ci-dessous)
POST   /establishments/:establishmentId/notifications/low-stock-check (stock.manage)
DELETE /establishments/:establishmentId/notifications                 (notifications.manage — Super Administrateur uniquement)
```

## Portée

Le schéma (Phase 3) définit une table `notifications` simple : `organizationId`, `userId` optionnel (`null` = diffusion à toute l'organisation), `title`, `body`, `readAt`. Aucune table de jetons push (FCM/APNs/Web Push) n'existe, et cet environnement n'a ni clé FCM ni configuration Web Push — les notifications **push** demandées implicitement par le prompt maître ne sont donc pas construites : seules des notifications **in-app** le sont, appuyées sur ce qui existe réellement dans le schéma.

## Particularité : `Notification` est rattachée à l'organisation, pas à l'établissement

Toutes les autres routes de cette application sont scopées par `establishmentId`. `NotificationsService.getOrganizationId` fait la traduction en une seule fonction, réutilisée par toutes les méthodes du service, et sert **aussi** de contrôle d'appartenance : `list`/`unreadCount`/`markAsRead` n'ont volontairement aucun `@RequirePermissions` (comme `GET /auth/me` ou `SyncController`) — n'importe quel membre de l'établissement peut lire ses propres notifications, et c'est cette fonction, pas le guard, qui empêche un utilisateur non affilié d'accéder aux notifications d'une autre organisation.

## Diffusion : opérationnelle pour tous les rôles (décision actée 2026-09-13)

`POST .../broadcast` n'exige plus `settings.manage` — comme `list`/`unreadCount`/`markAsRead`, seule l'appartenance à l'établissement (`getOrganizationId`) est vérifiée. Demande utilisateur explicite : diffuser un message doit être une fonctionnalité opérationnelle par tous les rôles, pas réservée à qui gère les paramètres de l'établissement.

## Badge « non lu » : disparaît après simple consultation, pas seulement après lecture individuelle (décision actée 2026-09-13)

Avant ce correctif, le badge rouge de l'accueil (`unreadCount`) ne diminuait que lorsqu'une notification était marquée lue **individuellement** (`markAsRead`, un appui par notification) — or une diffusion (`userId` nul) ne peut jamais être marquée lue par un individu (voir la limite documentée ci-dessous), donc son badge ne disparaissait jamais tant que personne n'avait, par définition, un moyen de la faire disparaître. Demande utilisateur : le badge doit disparaître dès que l'utilisateur a simplement **consulté** l'écran Notifications, sans avoir à ouvrir chaque élément.

Nouveau champ `UserProfile.notificationsViewedAt` (migration `20260913115537_add_user_profile_notifications_viewed_at.sql`), mis à jour à **chaque appel de `NotificationsService.list`** (donc à chaque ouverture de l'écran) :
- `unreadCount` ne compte plus que les notifications dont `createdAt` est postérieur à ce marqueur (en plus de `readAt: null`, gardé pour la cohérence individuelle) — une notification déjà là lors de la dernière consultation ne recompte jamais, que ce soit une diffusion ou une notification ciblée jamais ouverte individuellement.
- `notificationsViewedAt` nul (jamais consulté) équivaut à "depuis toujours" : comportement inchangé pour un compte qui n'a encore jamais ouvert l'écran.
- Contrairement à `SupabaseJwtGuard.recordLastSeen` (`lastSeenAt`, best-effort, jamais attendu), cette écriture est **attendue avant de renvoyer la liste** — la justesse du badge dépend directement de ce marqueur, une perte occasionnelle ne serait pas acceptable ici comme elle l'est pour un simple indicateur de présence.

## Effacer toutes les notifications : réservé au Super Administrateur (décision actée 2026-09-13)

Nouvelle permission `notifications.manage`, **volontairement exclue** du bloc "accès complet" du seed (qui donne normalement toutes les permissions à Super Administrateur/Administrateur/Propriétaire) et accordée séparément au seul Super Administrateur — voir `supabase/seed/001_roles_permissions.sql`. `DELETE .../notifications` (`NotificationsService.clearAll`) supprime **toutes** les notifications de l'organisation, ciblées ou diffusées, sans distinction — une action destructive et irréversible, jamais un simple marquage lu.

Côté Flutter, le bouton correspondant (icône balai, `lib/notifications/notifications_page.dart`) n'est affiché que si `roleName == 'Super Administrateur'` — un confort d'affichage, la vraie protection restant le refus serveur (403) pour quiconque n'a pas `notifications.manage`. Confirmation obligatoire avant l'appel (même motif que `UsersPage._removeMember`).

## Limite documentée : une notification diffusée ne peut pas être marquée lue individuellement

`readAt` est une colonne unique sur la ligne `Notification` — pour une notification ciblée (`userId` non nul), la marquer lue n'affecte qu'un seul destinataire, cohérent. Pour une diffusion (`userId` nul), il n'existe pas de table de suivi de lecture par utilisateur dans le schéma ; `markAsRead` refuse donc (404) toute tentative sur une notification qui n'est pas explicitement adressée à l'appelant. Une diffusion reste visible indéfiniment comme non lue pour tout le monde — acceptable pour de simples annonces, documenté plutôt que contourné par une fausse table.

## Génération automatique : toute saisie sur une action financière/stock clé

En plus des alertes de stock bas ci-dessous, **toute vente, tout achat reçu, toute dépense, toute perte, tout mouvement de stock manuel et toute clôture de caisse** génère automatiquement une notification de diffusion (visible par toute l'organisation dans Notifications) — décision explicite de l'utilisateur (2026-09-08), volontairement bornée à ces 6 actions plutôt qu'à *toute* modification de l'application : les changements mineurs de catalogue (créer/modifier une catégorie, changer un prix) ne notifient pas, pour éviter un flux de notifications ingérable.

Portée par `ActivityNotifierService` (`apps/api/nestjs/src/notifications/activity-notifier.service.ts`), **volontairement dans son propre module** (`ActivityNotifierModule`), sans dépendre de `NotificationsService` ni en être dépendu : `NotificationsService` dépend déjà de `StockModule` (alertes de stock bas), et `StockModule` doit pouvoir notifier lui aussi — les faire dépendre l'un de l'autre créerait un cycle de modules. Cette classe ne fait qu'écrire une notification broadcast (`userId: null`), sans les autres responsabilités (lecture, marquage lu) de `NotificationsService`.

Chaque service métier concerné (`SalesService.create`, `PurchasesService.receive`, `ExpensesService.create`, `LossesService.create`, `StockMovementsService.create`, `CashService.close`) appelle `activityNotifier.notify(establishmentId, title, body)` **après** l'écriture réussie — jamais avant, et jamais sur un rejeu idempotent déjà traité (une dépense ou une vente rejouée par la file de synchronisation hors ligne ne notifie qu'une fois, à sa toute première écriture réelle). Une notification manquée (établissement introuvable, cas qui ne devrait jamais arriver) est journalisée côté serveur sans jamais faire échouer l'action métier elle-même.

## Génération automatique : alertes de stock bas

`POST .../notifications/low-stock-check` réutilise `StockMovementsService.listLowStockAlerts` (Phase 6) tel quel et crée une notification de diffusion par produit en alerte — sauf s'il en existe déjà une non lue avec le même titre (évite l'empilement de doublons à chaque appel). **Aucun ordonnanceur n'est configuré dans cet environnement** (pas de cron, voir `PROJECT_PLAN.md`) : cette route est pensée pour être appelée à la demande pour l'instant, et par une vraie tâche planifiée le jour où l'infrastructure de déploiement en aura une, sans changer son contrat.

## UI Flutter (`lib/notifications/`)

Liste (gras = non lu, appui = marque lu si c'est une notification ciblée), bouton « Diffuser un message » (annonce libre, opérationnel pour tous les rôles depuis le 2026-09-13), bouton « Vérifier les stocks bas » (déclenche `low-stock-check`, `stock.manage`), et bouton « Effacer toutes les notifications » (icône balai) **visible uniquement pour le rôle Super Administrateur**. En dehors de ce dernier bouton — une exception délibérée, demande explicite de l'utilisateur —, comme le reste de l'application, aucun bouton n'est masqué selon les permissions côté client : un refus serveur (403) s'affiche normalement via le message d'erreur générique.

`NotificationsPage` exige désormais `roleName` (en plus de `establishmentId`), passé par `HomeDashboard` depuis ses deux points d'entrée (icône cloche de l'AppBar, tuile « Notifications » de PILOTAGE).

## Vérifications effectuées

- `NotificationsService` : 17 tests (Prisma mocké) — rejet d'un non-membre, filtrage diffusion + ciblé, marquage lu restreint aux notifications ciblées, rejet d'un destinataire hors organisation, dédoublonnage des alertes de stock bas, **`notificationsViewedAt` mis à jour à chaque `list`, `unreadCount` filtré par ce marqueur (avec et sans consultation préalable), `clearAll` supprime toute l'organisation et rejette un non-membre** (2026-09-13).
- `ActivityNotifierService` appelé depuis chaque service métier : vérifié par un test dédié dans chacun des 6 fichiers de spec concernés (`sales`, `purchases`, `expenses`, `losses`, `stock-movements`, `cash`) — contenu du message, et absence de notification sur un rejeu idempotent déjà traité (`expenses`, `losses`, `sales`).
- UI Flutter : `flutter analyze`/`flutter test`/`flutter build web` ✅, y compris la validation du formulaire de diffusion et la visibilité conditionnelle du bouton « Effacer tout » (3 nouveaux tests, 2026-09-13).
- **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.
