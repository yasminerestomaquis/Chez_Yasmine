# Dépenses — Chez Yasmine

## Routes

```
GET    /establishments/:establishmentId/expenses?from=&to=   (expenses.manage)
POST   /establishments/:establishmentId/expenses              (expenses.manage)
PATCH  /establishments/:establishmentId/expenses/:expenseId   (expenses.manage)
DELETE /establishments/:establishmentId/expenses/:expenseId   (expenses.manage)
```

## Champs

`label` (obligatoire), `category` (texte libre — voir plus bas), `amount` (obligatoire, > 0), `expenseDate` (par défaut aujourd'hui), `periodicity` (`one_off` | `recurring`, par défaut `one_off`), `note`.

## Nature de la dépense (`category`) : liste prédéfinie, non fermée

`kPredefinedExpenseCategories` (`apps/web/flutter/lib/expenses/expense_models.dart`) propose 9 natures courantes pour un maquis-bar : Loyer, Salaires, Cie (électricité), Eau, Patentes, Entretien, Bouteilles de gaz, Charbon, Marché. « Marché » (ajoutée le 2026-09-08) est l'achat journalier des produits des catégories du Catalogue à prix variable (Poulets, Poissons, Plats africains — `Category.hasVariablePricing`, voir `docs/api/catalog.md`) : ces catégories n'ont pas de prix d'achat par produit dans le catalogue, leur coût est donc capté ici, de façon agrégée, plutôt que ligne par ligne comme un achat fournisseur classique (module Achats). Comme toute dépense, elle compte déjà dans le calcul du bénéfice net (`docs/api/reports.md`) sans code supplémentaire — le filtrage par période dans `ReportsService` ne distingue pas les natures de dépense. Le formulaire Flutter les présente dans un menu déroulant avec une option « Autre… » qui révèle un champ de saisie libre — décision explicite de l'utilisateur (2026-09-08) : la liste **n'est jamais fermée** côté validation. `category` reste un `string` libre non contraint par une énumération côté API (`CreateExpenseDto`/`UpdateExpenseDto`), pour ne jamais rejeter une nature saisie hors de cette liste. Les graphiques par catégorie de dépenses (voir `docs/api/charts.md`) affichent donc aussi bien les 8 catégories prédéfinies que toute catégorie personnalisée effectivement utilisée.

## Périodicité (`periodicity`) : étiquette informative, pas d'automatisation

`one_off` (ponctuelle) ou `recurring` (récurrente) — décision explicite de l'utilisateur (2026-09-08) de s'en tenir à une simple étiquette plutôt qu'à un moteur de récurrence : **aucune dépense n'est générée automatiquement** d'un mois sur l'autre. Une dépense marquée récurrente doit être ressaisie à chaque échéance, exactement comme une dépense ponctuelle. Cette étiquette n'affecte en rien le calcul du bénéfice net (`docs/api/reports.md`) : toute dépense compte déjà dans ce calcul, quelle que soit sa périodicité — ce champ n'est qu'une information affichée à l'utilisateur (et un filtre potentiel futur), jamais un déclencheur.

## Synchronisation hors ligne

Ajouté au moteur de synchronisation générique (`docs/api/sync.md`, `entityType: 'expense'`, permission `expenses.manage`) : une dépense saisie sans réseau ne fait plus jamais échouer l'écran, elle est mise en file locale (`SyncQueueService`, même mécanisme que les ventes et les mouvements de stock) puis rejouée dès le retour de connexion. `ExpensesService.create` accepte un `id` client (UUID) et rejoue l'opération de façon idempotente — un identifiant déjà enregistré renvoie la dépense existante sans créer de doublon ni notifier une seconde fois (voir `docs/api/notifications.md`).

## Notification automatique

Toute dépense enregistrée avec succès notifie toute l'organisation (« Nouvelle dépense » — libellé, montant, catégorie), sauf sur un rejeu idempotent déjà traité. Voir `docs/api/notifications.md` pour le mécanisme général.

## Vérifications effectuées

- `ExpensesService` : tests couvrant le filtrage par période, la mise à jour/suppression scopées par établissement, la valeur par défaut et la transmission de `periodicity`, le rejeu idempotent d'une création (aucun doublon, aucune notification en double), et la notification de l'organisation sur une création réelle.
- UI Flutter (`lib/expenses/`) : menu déroulant des 8 catégories prédéfinies + option « Autre » révélant un champ libre, sélecteur de périodicité (`SegmentedButton`), file de synchronisation hors ligne montée (`SyncStatusBar`) — `flutter analyze` ✅, tests widget dédiés.
- **Non vérifié en conditions réelles** : un scénario hors-ligne→ligne complet pour une dépense (coupure réseau réelle, retour, synchronisation) — à faire à l'occasion d'une prochaine vérification en conditions réelles.
