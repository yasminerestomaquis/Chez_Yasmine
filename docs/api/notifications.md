# Notifications — Chez Yasmine

## Routes

```
GET   /establishments/:establishmentId/notifications                 (authentifié, pas de permission dédiée)
GET   /establishments/:establishmentId/notifications/unread-count    (authentifié)
PATCH /establishments/:establishmentId/notifications/:id/read        (authentifié)
POST  /establishments/:establishmentId/notifications/broadcast       (settings.manage)
POST  /establishments/:establishmentId/notifications/low-stock-check (stock.manage)
```

## Portée

Le schéma (Phase 3) définit une table `notifications` simple : `organizationId`, `userId` optionnel (`null` = diffusion à toute l'organisation), `title`, `body`, `readAt`. Aucune table de jetons push (FCM/APNs/Web Push) n'existe, et cet environnement n'a ni clé FCM ni configuration Web Push — les notifications **push** demandées implicitement par le prompt maître ne sont donc pas construites : seules des notifications **in-app** le sont, appuyées sur ce qui existe réellement dans le schéma.

## Particularité : `Notification` est rattachée à l'organisation, pas à l'établissement

Toutes les autres routes de cette application sont scopées par `establishmentId`. `NotificationsService.getOrganizationId` fait la traduction en une seule fonction, réutilisée par toutes les méthodes du service, et sert **aussi** de contrôle d'appartenance : `list`/`unreadCount`/`markAsRead` n'ont volontairement aucun `@RequirePermissions` (comme `GET /auth/me` ou `SyncController`) — n'importe quel membre de l'établissement peut lire ses propres notifications, et c'est cette fonction, pas le guard, qui empêche un utilisateur non affilié d'accéder aux notifications d'une autre organisation.

## Limite documentée : une notification diffusée ne peut pas être marquée lue individuellement

`readAt` est une colonne unique sur la ligne `Notification` — pour une notification ciblée (`userId` non nul), la marquer lue n'affecte qu'un seul destinataire, cohérent. Pour une diffusion (`userId` nul), il n'existe pas de table de suivi de lecture par utilisateur dans le schéma ; `markAsRead` refuse donc (404) toute tentative sur une notification qui n'est pas explicitement adressée à l'appelant. Une diffusion reste visible indéfiniment comme non lue pour tout le monde — acceptable pour de simples annonces, documenté plutôt que contourné par une fausse table.

## Génération automatique : alertes de stock bas

`POST .../notifications/low-stock-check` réutilise `StockMovementsService.listLowStockAlerts` (Phase 6) tel quel et crée une notification de diffusion par produit en alerte — sauf s'il en existe déjà une non lue avec le même titre (évite l'empilement de doublons à chaque appel). **Aucun ordonnanceur n'est configuré dans cet environnement** (pas de cron, voir `PROJECT_PLAN.md`) : cette route est pensée pour être appelée à la demande pour l'instant, et par une vraie tâche planifiée le jour où l'infrastructure de déploiement en aura une, sans changer son contrat.

## UI Flutter (`lib/notifications/`)

Liste (gras = non lu, appui = marque lu si c'est une notification ciblée), bouton « Diffuser un message » (annonce libre, `settings.manage`), bouton « Vérifier les stocks bas » (déclenche `low-stock-check`, `stock.manage`). Comme le reste de l'application, aucun bouton n'est masqué selon les permissions côté client — un refus serveur (403) s'affiche normalement via le message d'erreur générique, cohérent avec le choix déjà fait pour tous les autres écrans.

## Vérifications effectuées

- `NotificationsService` : 9 tests (Prisma mocké) — rejet d'un non-membre, filtrage diffusion + ciblé, marquage lu restreint aux notifications ciblées, rejet d'un destinataire hors organisation, dédoublonnage des alertes de stock bas.
- UI Flutter : `flutter analyze`/`flutter test`/`flutter build web` ✅, y compris la validation du formulaire de diffusion.
- **Non vérifié en conditions réelles** : round-trip HTTP complet — même limitation `DATABASE_URL` que les phases précédentes.
