# Dépenses — Chez Yasmine

## Routes

```
GET    /establishments/:establishmentId/expenses?from=&to=            (expenses.manage)
GET    /establishments/:establishmentId/expenses/next-market-number   (expenses.manage)
POST   /establishments/:establishmentId/expenses                       (expenses.manage)
PATCH  /establishments/:establishmentId/expenses/:expenseId            (expenses.manage)
DELETE /establishments/:establishmentId/expenses/:expenseId            (expenses.manage)
```

## Champs

`label` (obligatoire), `category` (texte libre — voir plus bas), `amount` (obligatoire, > 0), `expenseDate` (par défaut aujourd'hui, éditable — voir ci-dessous), `periodicity` (`one_off` | `recurring`, par défaut `one_off`), `note`, `marketNumber` (entier optionnel — voir ci-dessous).

### N° de marché (décision actée 2026-09-10)

Pour une dépense de nature **« Marché »**, le formulaire Flutter affiche un champ **N° de marché** supplémentaire, suggéré et librement éditable — même principe que `Purchase.orderNumber` (`docs/api/purchasing.md`) : `GET .../expenses/next-market-number` renvoie `{ marketNumber }`, dernier `marketNumber` connu (toutes dépenses `category === 'Marché'` de l'établissement, quelle que soit la date) + 1, ou 1 s'il n'y en a aucune. Jamais imposé ni contraint en unicité côté serveur — l'utilisateur reste maître du numéro affiché, un doublon ou un trou n'empêche jamais l'enregistrement. Stocké sur `Expense.marketNumber` (`Int?`, migration `20260910180000_add_expense_market_number.sql`), affiché dans la liste sous la forme « Marché n°3 » quand renseigné. Sans rapport avec l'allocation du coût aux ventes (`docs/api/charts.md`), qui reste basée sur `expenseDate` et `category` uniquement — ce numéro est une simple aide au suivi/pointage des marchés successifs, pas une clé de calcul.

### Date de la dépense éditable (décision actée 2026-09-10)

Le formulaire Flutter (`_addExpense` dans `lib/expenses/expenses_page.dart`) propose un sélecteur de date (`showDatePicker`, même composant que le module Achats), pré-rempli à aujourd'hui mais librement modifiable — nécessaire en particulier pour saisir la dépense **« Marché »** (voir ci-dessous) un autre jour que celui de la saisie, par exemple a posteriori en fin de journée ou en rattrapage d'un jour oublié. `ExpensesRepository.createExpense` transmet `expenseDate` au format `YYYY-MM-DD` (`@db.Date` côté schéma, sans composante horaire) ; `CreateExpenseDto`/`ExpensesService.create` l'acceptaient déjà (`@IsOptional() @IsDateString()`, défaut `now()` uniquement si omis) — seul le formulaire Flutter ne l'exposait pas jusqu'ici. Répercuté aussi dans le payload de la file de synchronisation hors ligne (`docs/api/sync.md`), pour qu'une dépense datée saisie hors ligne conserve sa date une fois rejouée.

## Nature de la dépense (`category`) : liste prédéfinie, non fermée

`kPredefinedExpenseCategories` (`apps/web/flutter/lib/expenses/expense_models.dart`) propose 9 natures courantes pour un maquis-bar : Loyer, Salaires, Cie (électricité), Eau, Patentes, Entretien, Bouteilles de gaz, Charbon, Marché. « Marché » (ajoutée le 2026-09-08) est l'achat journalier des produits des catégories du Catalogue à prix variable (Poulets, Poissons, Plats africains — `Category.hasVariablePricing`, voir `docs/api/catalog.md`) : ces catégories n'ont pas de prix d'achat par produit dans le catalogue (décision actée 2026-09-10, voir `docs/api/purchasing.md`), leur coût est donc capté ici, de façon agrégée, plutôt que ligne par ligne comme un achat fournisseur classique (module Achats) — **une saisie par jour d'achat**, grâce à la date éditable ci-dessus, est ce qui permet au module Graphiques de répartir ce montant entre les ventes du même jour au prorata du chiffre d'affaires (`docs/api/charts.md`). Comme toute dépense, elle compte déjà dans le calcul du bénéfice net (`docs/api/reports.md`) sans code supplémentaire — le filtrage par période dans `ReportsService` ne distingue pas les natures de dépense. Le formulaire Flutter les présente dans un menu déroulant avec une option « Autre… » qui révèle un champ de saisie libre — décision explicite de l'utilisateur (2026-09-08) : la liste **n'est jamais fermée** côté validation. `category` reste un `string` libre non contraint par une énumération côté API (`CreateExpenseDto`/`UpdateExpenseDto`), pour ne jamais rejeter une nature saisie hors de cette liste. Les graphiques par catégorie de dépenses (voir `docs/api/charts.md`) affichent donc aussi bien les 8 catégories prédéfinies que toute catégorie personnalisée effectivement utilisée.

## Périodicité (`periodicity`) : étiquette informative, pas d'automatisation

`one_off` (ponctuelle) ou `recurring` (récurrente) — décision explicite de l'utilisateur (2026-09-08) de s'en tenir à une simple étiquette plutôt qu'à un moteur de récurrence : **aucune dépense n'est générée automatiquement** d'un mois sur l'autre. Une dépense marquée récurrente doit être ressaisie à chaque échéance, exactement comme une dépense ponctuelle. Cette étiquette n'affecte en rien le calcul du bénéfice net (`docs/api/reports.md`) : toute dépense compte déjà dans ce calcul, quelle que soit sa périodicité — ce champ n'est qu'une information affichée à l'utilisateur (et un filtre potentiel futur), jamais un déclencheur.

## Synchronisation hors ligne

Ajouté au moteur de synchronisation générique (`docs/api/sync.md`, `entityType: 'expense'`, permission `expenses.manage`) : une dépense saisie sans réseau ne fait plus jamais échouer l'écran, elle est mise en file locale (`SyncQueueService`, même mécanisme que les ventes et les mouvements de stock) puis rejouée dès le retour de connexion. `ExpensesService.create` accepte un `id` client (UUID) et rejoue l'opération de façon idempotente — un identifiant déjà enregistré renvoie la dépense existante sans créer de doublon ni notifier une seconde fois (voir `docs/api/notifications.md`).

## Notification automatique

Toute dépense enregistrée avec succès notifie toute l'organisation (« Nouvelle dépense » — libellé, montant, catégorie), sauf sur un rejeu idempotent déjà traité. Voir `docs/api/notifications.md` pour le mécanisme général.

## Vérifications effectuées

- `ExpensesService` : tests couvrant le filtrage par période, la mise à jour/suppression scopées par établissement, la valeur par défaut et la transmission de `periodicity`, le rejeu idempotent d'une création (aucun doublon, aucune notification en double), la notification de l'organisation sur une création réelle, la transmission de `marketNumber`, et `nextMarketNumber` (1 si aucune dépense « Marché », dernier + 1 sinon, scopé à `category === 'Marché'`).
- UI Flutter (`lib/expenses/`) : menu déroulant des 9 catégories prédéfinies + option « Autre » révélant un champ libre, sélecteur de date (défaut aujourd'hui, librement modifiable), champ N° de marché (affiché uniquement pour « Marché », suggéré puis éditable), sélecteur de périodicité (`SegmentedButton`), file de synchronisation hors ligne montée (`SyncStatusBar`) — `flutter analyze`/`test`/`build web` ✅.
- **Vérifié en conditions réelles** (2026-09-10, compte de démonstration jetable, établissement réel « Chez Yasmine ») : saisie d'une dépense « Marché » datée la veille via l'application déployée, `expense_date` confirmée en base distincte de `created_at`, allocation pro-rata reflétée dans Graphiques → Bénéfices (voir `docs/api/charts.md`), puis nettoyage complet (dépense, vente/produit de test, compte jetable).
- **Non vérifié en conditions réelles** : un scénario hors-ligne→ligne complet pour une dépense (coupure réseau réelle, retour, synchronisation) — à faire à l'occasion d'une prochaine vérification en conditions réelles.
