# Graphiques — Chez Yasmine

## Routes

Toutes protégées par `SupabaseJwtGuard` + `PermissionsGuard` + `@RequirePermissions('reports.view')` — même permission que le module Rapports, puisqu'il s'agit de la même donnée métier, seulement visualisée différemment.

```
GET /establishments/:establishmentId/charts/weekly?metric=revenue|profit&weekStart=YYYY-MM-DD
GET /establishments/:establishmentId/charts/weekly-by-category?metric=&weekStart=&categoryIds=
GET /establishments/:establishmentId/charts/weekly-by-product?metric=&weekStart=&productIds=
GET /establishments/:establishmentId/charts/monthly?metric=revenue|profit&year=YYYY
GET /establishments/:establishmentId/charts/top?metric=revenue|profit&from=&to=
GET /establishments/:establishmentId/charts/stock-lots?productIds=
GET /establishments/:establishmentId/charts/out-of-stock-products
GET /establishments/:establishmentId/charts/active-stock-listing
GET /establishments/:establishmentId/charts/active-stock-listing.pdf
GET /establishments/:establishmentId/charts/meals-profit-listing
GET /establishments/:establishmentId/charts/meals-profit-listing.pdf
GET /establishments/:establishmentId/charts/expenses/weekly?weekStart=YYYY-MM-DD
GET /establishments/:establishmentId/charts/expenses/weekly-by-category?weekStart=&categories=
GET /establishments/:establishmentId/charts/expenses/monthly?year=YYYY
GET /establishments/:establishmentId/charts/expenses/top?from=&to=
```

`metric` est obligatoire sur les routes Recettes/Bénéfices : `revenue` ou `profit`. `stock-lots` et les routes `expenses/*` n'ont pas de `metric` — une seule grandeur possible dans chaque cas (voir leurs sections dédiées).

## Permissions par graphique (décision actée 2026-09-20)

`reports.view` ne gate plus ce module : **une permission par graphique** (`charts.<sous-module>_<graphique>`, 17 au total depuis le 2026-09-25), affichées dans « Gestion des permissions » (module Utilisateurs) sous **Graphiques** > Recettes / Bénéfices / Stock / Dépenses :

| Sous-module | Permissions |
|---|---|
| Recettes (5) | `charts.revenue_daily`, `_by_category`, `_by_product`, `_top`, `_monthly` |
| Bénéfices (6) | `charts.profit_daily`, `_by_category`, `_by_product`, `_top`, `_monthly`, `_meals_listing` (listing "Repas", 2026-09-25) |
| Stock (2) | `charts.stock_lots` (Détail d'un produit), `charts.stock_out` (Top des produits épuisés) — le listing "Stock actif" utilise `stock.active_listing`, voir plus bas, pas une permission `charts.*` bien que sa route vive ici |
| Dépenses (4) | `charts.expenses_daily`, `_by_category`, `_top`, `_monthly` |

- **Serveur** : `PermissionsGuard` ne sait gater qu'un code statique par route alors que le code dépend ici du paramètre `metric` (Recettes/Bénéfices) ; `ChartsController` vérifie donc la permission dans chaque méthode (`AuthorizationService`, liste canonique dans `src/charts/chart-permissions.ts`). Un non-membre de l'établissement n'a aucun code, donc est refusé partout. Nouvelle route `GET .../charts/permissions` : renvoie les codes `charts.*` de l'appelant.
- **Migration sans changement de comportement** : tout rôle qui portait `reports.view` reçoit les 16 permissions (seed + production : Administrateur, Caissier, Comptable, Gérant, Propriétaire, Serveur, Super Administrateur — 16 chacun). Rien ne change tant qu'un graphique n'est pas refusé explicitement ; noter que le Serveur (qui a `reports.view` pour les cartes de l'Accueil) garde donc l'accès aux graphiques jusqu'à ce qu'on le lui retire dans la matrice.
- **Flutter** : `GraphiquesPage` charge `/charts/permissions` et passe l'ensemble aux onglets ; un graphique refusé n'est ni affiché ni interrogé, une section sans aucun graphique autorisé affiche un message. Si le chargement échoue (hors ligne), tous sont proposés — le serveur refuse de toute façon. Si « journalier » est refusé, le sélecteur de semaine (qui s'y trouvait) apparaît dans le graphique autorisé suivant.
- **Effet de bord voulu** : la courbe hebdomadaire de Rapports (`getWeekly(revenue)`) exige désormais `charts.revenue_daily` ; elle est déjà non bloquante côté Flutter.

## Définitions retenues (à lire avant toute autre chose)

- **Recettes** = chiffre d'affaires ligne à ligne (`SaleItem.quantity × SaleItem.unitPrice`), jamais réduit par une remise (les remises ne sont enregistrées qu'au niveau de la vente entière, pas par ligne, voir `docs/api/pos.md`). Même le graphique "total" sans filtre additionne ces lignes plutôt que `Sale.total`, précisément pour que la somme des graphiques par catégorie/par produit reconcilie toujours avec le total journalier. Conséquence assumée : ce total peut légèrement différer du "chiffre d'affaires" affiché dans le module **Rapports** (qui utilise `Sale.total`, net de remise) — un choix de cohérence interne à ce module plutôt qu'un alignement strict avec Rapports.
- **Bénéfices, vues par catégorie/produit** (`weeklyByCategory`, `weeklyByProduct`, `top`) = marge brute (`revenue − coût`) uniquement, **jamais** le bénéfice net après dépenses/pertes. Les dépenses générales et les pertes ne sont pas rattachées à un produit ou une catégorie ; il n'existe donc aucune façon correcte de les y répartir — **sauf exception documentée ci-dessous pour Poulets/Poissons/Plats africains** (dépense « Marché »). Pour toute autre catégorie, le coût utilisé est `quantité × prix d'achat actuel du produit` (même simplification que `productProfitability`/`cogs` côté Rapports : le prix d'achat utilisé est celui du produit *aujourd'hui*, pas celui en vigueur au moment de chaque vente historique).
- **Bénéfices, vue "Total"** (`weeklyTotal`, `monthly`, sans filtre catégorie/produit) = **bénéfice net**, décision actée 2026-09-13 (voir section dédiée ci-dessous) : marge brute moins TOUTES les natures de dépenses (pas seulement « Marché ») et les pertes enregistrées de la période.

## Coût des catégories à prix variable : répartition de la dépense « Marché » (décision actée 2026-09-10)

Poulets, Poissons, Plats africains (`Category.hasVariablePricing`) n'ont jamais de `Product.purchasePrice` (leur prix d'achat varie trop d'un jour à l'autre pour qu'une valeur figée sur la fiche produit soit fiable — voir `docs/api/purchasing.md`). Sans correction, `effectiveUnitCost()` renverrait 0 pour ces produits et gonflerait artificiellement leur bénéfice affiché dans ce module.

`ChartsService.soldLines()` corrige cela en une seule fois, en aval de `effectiveUnitCost()`, pour que les 5 graphiques Bénéfices (`weeklyTotal`, `weeklyByCategory`, `weeklyByProduct`, `monthly`, `top`) en héritent automatiquement sans logique dupliquée :

1. Pour chaque **jour civil** (heure locale, même convention que `weekdayIndex`/`mondayOf`) de la période demandée, additionner le montant des dépenses de nature **« Marché »** (`Expense.category`, `Expense.expenseDate`) enregistrées ce jour-là.
2. Répartir ce total entre les lignes de vente de ce même jour appartenant à une catégorie `hasVariablePricing`, **au prorata du chiffre d'affaires de chaque ligne** ce jour-là (`ligne.revenue / Σ revenue du jour pour ces catégories`).
3. Le coût ainsi calculé remplace celui de `effectiveUnitCost()` pour ces lignes uniquement — les catégories à prix fixe/par casier ne sont jamais concernées.

**Cas limite assumé** : un jour avec des ventes Poulets/Poissons/Plats africains mais **aucune** dépense « Marché » saisie ce jour-là a un coût alloué de **0** pour ce jour (bénéfice apparent = 100% du chiffre d'affaires) — c'est un signal qu'il manque une saisie, pas une erreur de calcul. D'où l'ajout d'un champ Date dans le formulaire de saisie de dépense (`docs/api/expenses.md`), pour permettre de saisir la dépense Marché un autre jour que "aujourd'hui" (après coup, ou en avance).

**Délibérément limité à `ChartsService`, pas répercuté dans `ReportsService`** : le bénéfice net global de Rapports (`netProfit`) est déjà exact, la dépense Marché y étant déjà déduite en tant que dépense d'établissement à plat — seule sa ventilation *par produit* (`productProfitability`), non utilisée ici, resterait imprécise pour ces 3 catégories. Corriger uniquement ce sous-module aurait dupliqué la même logique d'allocation sans bénéfice pour l'indicateur global déjà correct (voir `docs/api/reports.md`).

**Choix historique abandonné** : un essai antérieur a étendu le module Achats à ces catégories pour y figer un "dernier prix d'achat connu" sur `Product.purchasePrice` — abandonné sur décision explicite de l'utilisateur (2026-09-10), ce prix variant trop d'un jour à l'autre pour ne pas fausser rétroactivement le bénéfice des jours précédant le dernier achat enregistré. Voir `docs/api/purchasing.md`.

## Bénéfice net de la vue "Total" : toutes les natures de dépenses + pertes (décision actée 2026-09-13)

Constat à l'origine de ce correctif : seule la nature « Marché » avait un rôle dans le calcul du bénéfice de ce module (ci-dessus) — les 8 autres natures prédéfinies (Loyer, Salaires, Cie, Eau, Patentes, Entretien, Bouteilles de gaz, Charbon) et les pertes enregistrées (module Pertes) n'en avaient aucun, contrairement au bénéfice net du module Rapports qui les inclut déjà toutes (à plat, sans lissage). Demande explicite : que `weeklyTotal`/`monthly` (metric `profit`) en tiennent compte, **en répartissant une dépense selon la récurrence de sa nature** plutôt qu'en la comptant en entier le seul jour où elle est payée (ce qui créerait un creux artificiel ce jour-là et un bénéfice surestimé le reste du temps) — exemple donné : un loyer mensuel ne doit peser que sur ~1/4 d'une semaine.

**Deux traitements selon la nature** (`AMORTIZED_CATEGORY_CYCLE_DAYS` dans `charts.service.ts`) :

- **Cycle long, réparti au prorata du recouvrement** : Loyer/Cie/Eau (cycle supposé 30 jours), Patentes (cycle supposé 365 jours). Pour la période `[from, to]` demandée (une semaine ou une année entière selon la granularité), chaque dépense de ces natures dans un cycle qui recouvre `[from, to]` — même si sa date réelle est *avant* `from` — contribue au prorata du nombre de jours de recouvrement (`amortizedOverheadTotal`, avec une fenêtre de recherche en arrière allant jusqu'au plus long cycle connu). Le total ainsi obtenu est **étalé à parts égales sur chaque case** de la série (chaque jour de la semaine, ou chaque mois de l'année) — au niveau mensuel, ce partage est linéaire (montant annuel / 12), pas pondéré par le nombre de jours du mois.
- **Cycle court ou inconnu, compté en entier à sa date réelle** : Salaires (déjà généré chaque semaine par le workflow de paie, voir `docs/api/expenses.md` — aucun lissage nécessaire), Entretien, Bouteilles de gaz, Charbon, toute catégorie personnalisée ("Autre") — et les **pertes enregistrées** (`Loss`, même calcul de coût que `ReportsService.summary`, `effectiveUnitCost`).
- **« Marché » reste exclue de ce mécanisme** : déjà imputée ligne à ligne par `allocateMarcheCost` (section précédente) — la recompter ici la compterait deux fois.

**Toujours pas répercuté sur les vues par catégorie/produit** (`weeklyByCategory`, `weeklyByProduct`, `top`) : le raisonnement de la section précédente reste valable pour ces 8 natures et les pertes — aucune ne peut être rattachée à un produit ou une catégorie de vente précis, contrairement à « Marché » qui a un lien logique direct avec les catégories à prix variable.

### Onglet Bénéfices réorganisé : « Bénéfice net » vs « Marge brute » (décision actée 2026-09-25)

Symptôme signalé : sur l'onglet Bénéfices, les 5 graphiques portaient tous le mot « Bénéfices » sans distinction, alors que `dailyTotal`/`monthly` calculent un **bénéfice net** (ci-dessus — marge moins toutes les dépenses et pertes) et que `dailyByCategory`/`dailyByProduct`/`top` calculent une **marge brute** (recette moins coût d'achat uniquement, jamais réduite par une dépense générale, pour les raisons données ci-dessus). Conséquence concrète observée : une même semaine pouvait afficher un Total négatif (ex. -50 763 FCFA, un jour de paie faisant un creux brutal puisque compté en entier à sa date réelle) à côté d'une ventilation par catégorie positive (+5 441 FCFA) sur la même période, sans rien pour expliquer l'écart — perçu à raison comme « pas logique ».

Aucun changement de calcul (les deux définitions restent justifiées, voir ci-dessus) — uniquement la présentation, côté Flutter (`lib/charts/metric_charts_tab.dart`, `graphiques_page.dart`) :

- Nouveaux intitulés explicites : « Bénéfice net — journalier »/« Bénéfice net — mensuel » (au lieu de « Bénéfices journaliers totaux »/« Bénéfices mensuels ») vs « Marge brute — journalière par catégorie »/« … par produit »/« Top marge brute (par produit) » (au lieu de « Bénéfices … »/« Top bénéfices »).
- `MetricChartsTab` gagne un paramètre `groupNetVsGross` (`true` uniquement pour Bénéfices, `false` — comportement inchangé — pour Recettes, qui n'a pas cette dualité) : quand actif, les 5 cartes sont regroupées sous deux en-têtes de section, « BÉNÉFICE NET » (Total, Mensuel) puis « MARGE BRUTE » (Par catégorie, Par produit, Top), chacun avec une phrase expliquant pourquoi les montants des deux sections ne se comparent pas directement.

### Listing « Repas » (onglet Bénéfices, `GET /charts/meals-profit-listing[.pdf]`, décision actée 2026-09-25)

Bouton dans l'AppBar de l'onglet Bénéfices (icône PDF, haut à droite — visible uniquement sur cet onglet, `GraphiquesPage._tabController` piloté explicitement pour ça, plus `DefaultTabController` implicite). Cumule les trois catégories à prix variable (Plats africains/Poissons/Poulets, `hasVariablePricing`) en **une seule ligne** — pas de ventilation par catégorie ni par produit — sur **tout l'historique** (pas de filtre de période, décision utilisateur, même convention que le listing Stock actif).

- `marketCost` : somme de toutes les dépenses de catégorie `'Marché'` **et** `'Bouteilles de gaz'` — les deux seules natures de dépense directement rattachables à l'approvisionnement des repas.
- `currentRevenue` : somme des lignes de vente (`SaleItem`, ventes non annulées) dont le produit appartient à une catégorie `hasVariablePricing` — même filtre que `ReportsService.paymentCategoryBreakdown` (groupe "Plats").
- `profit = currentRevenue - marketCost`. **Confirmé explicitement par l'utilisateur le 2026-09-25** : la formule "dépenses − recettes" de la demande d'origine aurait donné un bénéfice négatif pour une activité rentable, incohérent avec `rate` attendu positif — clarifié avant implémentation plutôt que supposé.
- `rate = profit × 100 / marketCost` (0 si `marketCost` est nul).

Colonnes (interface et PDF, cinq) : Repas, Prix marché, Recette actuelle, Bénéfice, Taux — exactement **deux lignes** de données ("Repas" puis "TOTAL", cette dernière identique à la première puisqu'il n'y a qu'une seule ligne agrégée, décision utilisateur — même convention "toujours une ligne TOTAL" que les autres listings). `GET .../meals-profit-listing.pdf` (`StreamableFile`, `drawPdfTable`, format portrait). Permission dédiée `charts.profit_meals_listing` (voir tableau ci-dessus) — namespacée sous `charts.profit_` pour se regrouper sous Bénéfices dans « Gestion des permissions », bien que ce ne soit pas un graphique `daily/by_category/by_product/top/monthly`.

## Semaine (graphiques 1, 2, 3, 6, 7, 8)

`weekStart` accepte n'importe quelle date : `ChartsService` la ramène systématiquement au **lundi** de cette semaine-là (`(date.getDay() + 6) % 7` pour un index 0=lundi..6=dimanche, contrairement à `Date.getDay()` natif où dimanche=0). La réponse renvoie `weekStart`/`weekEnd` résolus, pour que l'UI affiche la plage réellement utilisée même si la date fournie n'était pas elle-même un lundi.

```json
{
  "weekStart": "2026-09-07",
  "weekEnd": "2026-09-13",
  "series": [
    { "id": null, "name": "Total", "points": [{ "day": "Lundi", "value": 12000 }, "... 7 entrées"] }
  ]
}
```

- `GET /charts/weekly` : toujours une seule série (`id: null`, `name: "Total"`).
- `GET /charts/weekly-by-category` : sans `categoryId`, une série par catégorie ayant vendu quelque chose cette semaine-là (triées par total décroissant), plus une série `"Sans catégorie"` (`id: null`) si des produits sans catégorie ont été vendus ; avec `categoryId`, une seule série pour cette catégorie.
- `GET /charts/weekly-by-product` : même principe, une série par produit vendu, ou une seule série agrégée quand `productIds` (CSV, sélection multiple, réinitialisable — demande utilisateur du 2026-09-22) est fourni ; `productId` (singulier) reste accepté pour compatibilité.

### Sélection multiple de semaines côté client (décision actée 2026-09-24)

`weekStart` reste **une seule semaine par requête** côté serveur (aucun changement d'API) — la sélection multiple du filtre « Choisir la semaine » (Recettes/Bénéfices/Dépenses, `MetricChartsTab`/`ExpenseChartsTab`) se résout côté Flutter, même principe que le filtre Date multi-sélection de l'Accueil (`mergeBreakdowns`, `lib/home/date_selection.dart`) :

- `lib/charts/week_selection.dart` : `mondayOfWeek` ramène chaque jour choisi à son lundi (dédoublonne deux dates de la même semaine ISO) ; `pickWeeks` (dialogue) affiche les semaines sélectionnées en puces retirables, avec « Ajouter une semaine » (sélecteur de date natif) et « Réinitialiser » ; `mergeWeeklyCharts` additionne, jour de semaine par jour de semaine (position dans le tableau `points`, pas par date calendaire), les graphiques de chaque semaine sélectionnée — fusion des séries par `id ?? name` (une série absente d'une semaine n'y contribue simplement pas), puis retri par total décroissant, comme le fait déjà le serveur pour une semaine seule.
- `_multiWeek()` (nouvelle méthode privée des deux onglets) déclenche une requête par semaine sélectionnée (`Future.wait`) puis fusionne — donc jusqu'à N requêtes réseau pour N semaines cochées, un aller-retour par graphique par semaine.
- Le bouton affiche « Choisir la semaine » pour 0/1 semaine, « N semaines sélectionnées » au-delà (`weekFilterLabel`) ; le libellé « Semaine du X au Y » du graphique "journalier total" bascule sur ce même texte dès 2 semaines sélectionnées (une plage "du X au Y" suggérerait à tort un intervalle continu).
- Tests : 8 Flutter (`week_selection_test.dart`).

### Graphique « Recettes des semaines » (onglet Recettes uniquement, décision actée 2026-09-25)

Nouvelle carte, en plus des 5 graphiques habituels — **uniquement sur l'onglet Recettes** (`MetricChartsTab.showWeeklyRevenueTrend`, `true` seulement pour Recettes dans `graphiques_page.dart`, sans permission dédiée). Une courbe (`WeeklyRevenueTrendChartWidget`, `fl_chart` `LineChart`, même style que `MonthlyLineChartWidget`) du total de recette **réalisé chaque semaine** depuis une semaine d'ancrage fixe, axe des x en `S1`, `S2`, `S3`...

- **S1 = lundi 14/09/2026 au dimanche 20/09/2026** (`weeklyRevenueTrendAnchor`, `lib/charts/week_selection.dart`) — fixe, indépendant du filtre Année de `GraphiquesPage` (contrairement aux 5 autres graphiques de l'onglet).
- `realizedWeeksSince(anchor, now)` énumère chaque lundi de S1 jusqu'à la semaine courante incluse — « les semaines réalisées ». Chaque semaine garde son numéro `Si` de façon fixe (position dans cette liste), qu'elle soit affichée ou non : décocher S2 dans le filtre laisse un trou sur la courbe entre S1 et S3, plutôt que de renuméroter S3 en S2 — S3 doit toujours désigner la même semaine calendaire.
- Pas de nouvelle route serveur : une requête `GET /charts/weekly?metric=revenue&weekStart=<lundi>` par semaine réalisée (`Future.wait`), le total de chacune lu depuis `WeeklyChart.total` (déjà exposé, utilisé ailleurs pour `WeekTotalBadge`) — jusqu'à N requêtes pour N semaines réalisées, un aller-retour par semaine, comme `_multiWeek` pour la sélection multiple ci-dessus (mécanisme différent : là, fusion en une seule série ; ici, un point distinct par semaine).
- Filtre multi-semaines dédié (`MetricChartsTab._pickTrendWeeks`, dialogue à cases à cocher) — **toutes les semaines cochées par défaut**, « Réinitialiser » revient à tout cocher (pas à une seule semaine, contrairement à `pickWeeks` : ici chaque semaine reste son propre point, une sélection à une seule semaine viderait la courbe sans raison).
- Tests : 5 Flutter (`week_selection_test.dart`, `realizedWeeksSince`/`weekTrendLabel`), 2 (`graphiques_page_test.dart`, carte visible sur Recettes seulement + libellé "Toutes les semaines" par défaut).

## Mois (graphiques 5, 10)

`GET /charts/monthly?year=2026` renvoie les 12 mois de l'année demandée (`Janvier`..`Décembre`), aucun filtre supplémentaire — c'est le seul graphique du module qui n'est piloté que par le filtre Année global.

## Classement (graphiques 4, 9)

`GET /charts/top?from=&to=` (par défaut : du 1er janvier de l'année en cours à maintenant, si omis). Le regroupement suit exactement la demande d'origine plutôt qu'un paramètre générique :

- `metric=revenue` → classe par **catégorie** ("type de produit").
- `metric=profit` → classe par **produit** individuel.

Plafonné à 10 lignes (comme `topProducts` dans Rapports).

```json
{ "from": "...", "to": "...", "groupBy": "category", "items": [{ "id": "...", "name": "Plats", "value": 125000 }] }
```

**Montant total de l'année en haut à droite** (décision actée 2026-09-25, demande utilisateur — « Top recettes »/« Top bénéfices ») : `MetricChartsTab` affiche `MonthlyChart.total` (somme des 12 mois, réutilise `_monthlyFuture` déjà chargé pour la carte "mensuelle" ci-dessous, même `metric`/année) via `WeekTotalBadge` — purement client, pas de nouvelle route. Contrairement aux `items` du classement lui-même (bornés par le filtre Mois de la carte, ou toute l'année si "Toute l'année"), ce total couvre toujours l'année entière du filtre Année de `GraphiquesPage`, indépendamment du filtre Mois de "Top".

## Sous-module Stock — lots FIFO (`GET /charts/stock-lots?productIds=`)

Maquette demandée pour une fiche de gestion de stock par lots (First In, First Out) : quelle part du stock actuel d'un ou plusieurs produits provient de quelle livraison. Aucun schéma dédié — reconstruit à la volée depuis l'historique existant des `StockMovement` (`apps/api/nestjs/src/stock/`), le même que celui qui alimente `product.stockQuantity` :

- Chaque mouvement `'in'` (réception d'achat via `PurchasesService.receive`, ou remboursement de vente via `SalesService.refund`) devient un **lot** indépendant, daté de `StockMovement.createdAt`, avec sa propre quantité restante.
- Chaque mouvement de sortie (`'out'`, `'sale'`, `'loss'`) est imputé aux lots existants **du plus ancien au plus récent** (FIFO) — un lot atteignant 0 restant devient `epuise` et disparaît des lots actifs, mais reste dans l'historique complet (traçabilité). Depuis 2026-09-10, la part de cette consommation imputable spécifiquement à une **perte** (`type: 'loss'`, seul créateur : `LossesService`) est comptée à part sur le lot (`lossQuantity`), distincte d'une vente ou d'une sortie manuelle — c'est cette valeur qui alimente la colonne **Perdu** de l'UI.
- `'adjustment'` (quantité absolue, pas relative — voir `stock-math.ts`) est traité comme la différence avec le total couru : une hausse crée un lot synthétique daté de l'ajustement, une baisse consomme les lots existants en FIFO. Cela préserve l'invariant « somme des restants des lots actifs == `product.stockQuantity` » même avec des corrections manuelles.
- La logique pure (aucun accès DB) vit dans `apps/api/nestjs/src/stock/stock-lots.ts` (`computeFifoLots`), testée isolément puis appelée par `ChartsService.stockLots` qui charge les mouvements des produits demandés triés par date et vérifie leur appartenance à l'établissement.

### Numérotation des lots ↔ commande/marché (décision actée 2026-09-10)

Principe demandé : un lot `L00N` doit correspondre exactement à la commande N°N (catégories à prix par casier — Bières, Vins, Sucreries) ou au marché N°N (catégories à prix variable — Poulets, Poissons, Plats africains) qui l'a réellement produit, et **ne doit pas s'afficher** si cette commande/ce marché n'existe pas pour l'établissement.

- `computeFifoLots` parse ce numéro directement depuis `StockMovement.reason` du mouvement `'in'` à l'origine du lot (`referenceNumber`, regex `/n[°o]\s*(\d+)/i` — capture aussi bien "Commande n°1" que "Correction commande n°1" ou "Marché n°2"). Cette fonction reste par ailleurs backward-compatible : son `code` séquentiel historique (`L001`, `L002`...) est inchangé si on l'appelle isolément.
- `ChartsService.stockLots` fait le lien : pour une sélection dont la catégorie est `hasCasePricing` ou `hasVariablePricing`, elle collecte tous les `referenceNumber` parsés, vérifie lesquels correspondent à un `Purchase.orderNumber` (catégorie à prix par casier) ou un `Expense.marketNumber` de nature "Marché" (catégorie à prix variable) réellement existant pour l'établissement, **renumérote** le `code` du lot avec ce numéro (`L${referenceNumber}`), et **écarte** tout lot dont le numéro est absent ou introuvable. Les catégories hors de ces deux groupes (aucune connue à ce jour) ne sont pas soumises à cette règle et gardent la numérotation séquentielle historique.
- Catégories à prix par casier : chaque réception d'achat porte déjà `reason: "Commande n°X"` (`PurchasesService`), donc rien à changer côté saisie — le principe s'applique automatiquement à l'historique existant.
- Catégories à prix variable : **aucun flux d'achat automatisé n'existe pour elles** (exclues du module Achats — voir `docs/api/purchasing.md`). Une entrée manuelle de stock (`POST .../stock-movements`, type `'in'`) sur un produit de ces catégories exige donc désormais un **N° de marché** (`CreateStockMovementDto.marketNumber`), validé contre une dépense "Marché" déjà enregistrée pour l'établissement (`StockMovementsService.create`, `BadRequestException` sinon) ; le motif stocké est construit automatiquement (`"Marché n°X — <motif utilisateur>"`), pour rester parsable par la même expression régulière.

### Audit du pipeline complet Achats → Stock → Graphiques (2026-09-25)

Suite au signalement d'un « Consommé » négatif (voir correctif ci-dessous), l'ensemble du pipeline a été audité (entrée via Achats en respectant `bottlesPerCase`, récupération par Stock, sorties Caisse/Tables, récupération par Stock, décompte par Graphiques). Résultat :

- Achats (`PurchasesService.resolveLines`), Caisse (`SalesService`, décrémentation atomique avec garde `stockQuantity: { gte: quantity }`) et Tables (délègue entièrement à Caisse, ne touche jamais le stock directement) sont sains.
- Trois faiblesses réelles trouvées et corrigées (voir aussi `docs/api/purchasing.md` et `docs/api/catalog.md`) :
  1. Le « Consommé » négatif lui-même (ci-dessous).
  2. `PurchasesService.reverseStock` enregistrait la quantité d'origine de la commande au lieu de la quantité réellement retirée quand le stock disponible était moindre.
  3. `ProductsService.create` n'enregistrait aucun mouvement de stock pour le « Stock initial » saisi à la création d'un produit — ce stock restait invisible pour `computeFifoLots`.
- **État constaté sur les produits existants** (avant correctif n°3, donc rétroactivement toujours vrai pour les produits déjà créés) : 15 produits sur 37 à catégorie gérée par lots ont un stock (`product.stockQuantity`) supérieur à la somme de leurs lots actifs — écart entre -1 et -52 unités selon le produit, entièrement expliqué par un stock initial saisi au Catalogue avant l'existence d'un mouvement compagnon. Le décompte total (`totalActiveUnits`) et par produit reste donc **inférieur à la réalité** pour ces 15 produits tant qu'aucune régularisation rétroactive (mouvement `'in'` de rattrapage, hors code applicatif) n'est appliquée. La vignette Stock (`stock_page.dart`, basée sur `product.stockQuantity`) n'est pas affectée — seul le sous-module Graphiques > Stock (basé sur les lots) l'est.

### Correctif : « Consommé » négatif sur un lot visible (2026-09-25)

Symptôme signalé en production : certains lots (ex. Chill, Rhino) affichaient un `consumedQuantity` négatif et un `remainingQuantity` supérieur au `receivedQuantity` de la commande (ex. reçu 12, restant 13, consommé -1).

Cause racine : `ChartsService.stockLots` rattache le restant d'un mouvement `'in'` sans N° de commande identifiable (comptage manuel, correction de vente, ancien mouvement legacy — voir la note dans `stock-lots.ts`) au **dernier lot visible** du produit, pour que la somme des lots reste égale au stock actuel. L'implémentation n'ajoutait ce restant qu'à `remainingQuantity`, jamais à `receivedQuantity` : dès que le lot visible n'avait pas encore été consommé d'autant que ce restant orphelin, `remainingQuantity` dépassait `receivedQuantity` et `consumedQuantity` (leur différence) devenait négatif.

Correctif : le stock orphelin est désormais ajouté à **`receivedQuantity` ET `remainingQuantity`** du lot cible, jamais à l'un des deux seulement — `consumedQuantity` reste donc celui déjà calculé pour ce lot avant rattachement (toujours ≥ 0). Cas limite corrigé au passage : si aucun lot visible n'existe pour accueillir ce stock orphelin (ex. la commande d'origine a été supprimée depuis), un lot synthétique (`code: "Ajustement"`, `referenceNumber: null`) est créé plutôt que de silencieusement exclure ce stock de `totalActiveUnits`. Purement un correctif de reconstruction — aucune migration de données : `stockLots` recalcule tout à la volée depuis `StockMovement` à chaque appel, donc le correctif s'applique immédiatement à tout l'historique existant dès son déploiement.

### Sélection multiple, filtre catégorie (revu 2026-09-17 : plus de filtre Produit, catégories multiples)

`productIds` (CSV) accepte un ou plusieurs identifiants produit — plus aucune contrainte de catégorie unique côté serveur depuis le 2026-09-17 (l'ancienne `BadRequestException` "même catégorie" a été retirée). Les lots de tous les produits sélectionnés sont fusionnés dans une seule chronologie, chaque lot portant `productId`/`productName` (utile dès que plus d'un produit est sélectionné).

### Listing « Stock actif » (module Stock, `GET /charts/active-stock-listing[.pdf]`, décision actée 2026-09-25)

Bouton d'export dans l'AppBar du module Stock (`stock_page.dart`, haut à droite, icône PDF) : un listing, une ligne par produit (jamais deux lignes pour le même), agrégé sur ses seuls lots FIFO de statut `'actif'` — même critère que « Lots actifs » ci-dessus. `ChartsService.activeStockListing` fait la somme, sur ces lots, de `receivedQuantity`/`lossQuantity`/`remainingQuantity` ; produits sans aucun lot actif absents du résultat (jamais approvisionnés, ou entièrement épuisés). Visibilité pilotée par la permission `stock.active_listing` (par défaut Super Administrateur seul, accordable à d'autres rôles depuis « Gestion des permissions » — voir plus bas et `docs/api/users.md`), **pas** un rôle codé en dur.

**`consommé` est net des pertes** (`consumedQuantity - lossQuantity` de chaque lot, `lossQuantity` étant une *part* de `consumedQuantity` — voir `StockLot` — pas un total distinct), pour que les colonnes s'additionnent proprement : `reçue = consommé + perdu + restant`. Chaque quantité vendable (Qté reçue/Consommé/Perdu/Restant) est valorisée à sa propre « Recette » au même prix de vente unitaire que les pertes (`salePrice` sinon `referenceSalePrice` sinon 0, voir `lossUnitSalePrice`/`reports/loss-revenue.ts`) — cohérent avec le « prix de vente attendu » déjà affiché ailleurs dans Stock. « Prix d'achat qté reçue » et « Bénéfice » (`receivedRevenue - purchaseValue`) utilisent le coût unitaire des graphiques Bénéfices (`effectiveUnitCost`, `catalog/product-cost.util.ts` — prix par casier ÷ bouteilles par casier pour une catégorie `hasCasePricing`, sinon `purchasePrice`).

Colonnes (interface et PDF, onze — demande utilisateur du 2026-09-25) : Produit, Qté reçue, Prix d'achat qté reçue, Recette qté reçue, Consommé, Recette consommé, Perdu, Recette perdue, Restant, Recette stock, Bénéfice — plus une ligne TOTAL sommant chaque colonne numérique.

**Catégories à prix variable toujours exclues** (Plats africains/Poissons/Poulets, `hasVariablePricing` — ces produits n'ont ni prix d'achat ni prix de vente fixes en catalogue, les colonnes ci-dessus n'auraient aucun sens) : filtrage appliqué côté service (`ChartsService.activeStockListing`), pas seulement côté client. Avant d'afficher le listing, un dialogue (`StockPage._pickStockListingCategories`) propose les catégories restantes en sélection multiple (`CheckboxListTile`, sélection vide = toutes) ; le choix (`categoryIds`, CSV) est transmis à `GET .../active-stock-listing` et à l'export PDF, qui ne peut donc que **restreindre davantage** la sélection déjà éligible, jamais réintroduire une catégorie à prix variable.

`GET .../active-stock-listing` (JSON, listing à l'écran) et `.../active-stock-listing.pdf` (`StreamableFile`, tableau à quadrillage complet via `drawPdfTable` — désormais partagé dans `src/common/pdf-table.util.ts`, déplacé hors du module Rapports puisque réutilisé ici ; format paysage vu le nombre de colonnes) partagent toutes deux la permission `stock.active_listing` (`STOCK_ACTIVE_LISTING_PERMISSION`, `stock-permissions.ts`) — un code dédié, distinct de `charts.stock_lots`, bien que la route vive dans `ChartsController` : le regroupement dans « Gestion des permissions » suit le préfixe du **code**, pas le contrôleur qui le sert, donc ce bouton apparaît sous Stock, pas Graphiques.

Côté Flutter, `StockPage` interroge `GET .../stock/permissions` (`StockController.myPermissions`, déjà existante pour `stock.view_value`) et masque le bouton si `stock.active_listing` n'est pas accordé — remplace la précédente comparaison par nom de rôle codée en dur (`_isSuperAdmin`, retirée). Le tableau à l'écran (avant export) réutilise `griddedTable` (`lib/common/gridded_table.dart`, extrait de `ReportsPage` le même jour) — quadrillage complet, défilement horizontal explicite, défilement vertical délégué à `AlertDialog(scrollable: true)`.

### « Quantité reçue » et le total du bas en litres pour Gbêlê (décision actée 2026-09-25)

Purement un affichage client (`lib/charts/stock_lots_tab.dart`) — aucun changement de route ni de calcul : quand **tous** les produits de la sélection courante sont à prix de référence variable (`Product.isReferencePriced`, ex. Gbêlê — `_isReferencePricedSelection`), la colonne « Quantité reçue » du tableau des lots devient « Quantité reçue (L) » et sa valeur (et celles de Consommé/Perdu/Restant, mêmes chiffres) reçoit le suffixe « L » ; le bandeau du bas (« TOTAL GBÊLÊ (LOTS ACTIFS) ») affiche « … L » au lieu de « … unités ». Mélanger Gbêlê avec un produit à prix par casier retombe sur l'affichage habituel (« unités »), les deux n'ayant pas la même unité physique.

Le gating "numéro de marché"/"numéro de commande" (catégories `hasVariablePricing`/`hasCasePricing`, voir plus haut) se calcule désormais **par produit, selon sa propre catégorie**, plutôt qu'en supposant une catégorie unique pour toute la sélection (`ChartsService.stockLots`) — un seul aller-retour `Purchase`/`Expense` au total, même avec des produits de catégories différentes à la fois.

Côté Flutter (`stock_lots_tab.dart`), le filtre Produit a été retiré : seul reste un filtre Catégorie à **sélection multiple** (`FilterChip`, même pattern que Recettes/Bénéfices/Dépenses), avec un chip « Toutes » qui réinitialise la sélection — sélection vide = tous les produits du catalogue, même convention que le filtre catégorie de `stock_page.dart`. Les tableaux "Lots actifs"/"Historique" suivent directement l'ensemble des produits appartenant aux catégories cochées.

```json
{
  "productIds": ["p1"],
  "productNames": ["Bière Flag 65cl"],
  "activeLots": [
    { "code": "L002", "productId": "p1", "productName": "Bière Flag 65cl", "receivedAt": "2025-09-05T08:00:00.000Z", "receivedQuantity": 150, "consumedQuantity": 70, "lossQuantity": 5, "remainingQuantity": 80, "status": "actif" }
  ],
  "historyLots": ["... tous les lots visibles après filtrage par commande/marché existant(e)"],
  "totalActiveUnits": 200
}
```

`activeLots` alimente l'onglet « Lots actifs (N) », `historyLots` (tous les lots visibles, tous statuts confondus) l'onglet « Historique (N) », `totalActiveUnits` la carte de synthèse — exclusivement la somme des restants des lots **actifs**, jamais affecté par l'onglet actuellement affiché.

**Divergence assumée avec le reste du module** : cette vue n'est PAS bornée par le filtre Année de `GraphiquesPage` — elle prend tout l'historique des produits, parce qu'elle représente l'état *courant* du stock, pas une période. Un lot reçu il y a plusieurs années peut rester actif aujourd'hui ; y appliquer un filtre Année casserait la lecture du stock réellement disponible.

### Top des produits épuisés (`GET /charts/out-of-stock-products`)

Sous le tableau principal : liste des produits actifs à `stockQuantity ≤ 0`, triés par **ordre alphabétique croissant** (`ChartsService.outOfStockProducts`) — seul critère "croissant" disponible en l'absence d'un autre axe numérique demandé dans la consigne (tous ces produits étant à 0, un tri par quantité serait sans effet). Indépendant de la sélection produit/catégorie du tableau de lots au-dessus.

## Sous-module Dépenses — 4 graphiques, pas 5 (`GET /charts/expenses/*`)

Décision explicite de l'utilisateur (2026-09-08) : plutôt que de forcer les dépenses dans les graphiques Recettes/Bénéfices existants (une dépense n'a ni produit ni catégorie de *produit* — seulement sa propre nature, Loyer/Eau/... voir `docs/api/expenses.md`), un sous-module séparé les regroupe. Il compte **4** graphiques, pas 5 : pas de "par produit", une dépense n'étant rattachée à aucun produit.

- `GET /charts/expenses/weekly` : total journalier (Lundi→Dimanche d'une semaine choisie), même résolution du lundi que les routes `weekly` existantes (`weekRange`/`buildWeekResponse` réutilisées telles quelles).
- `GET /charts/expenses/weekly-by-category` : idem, ventilé par nature de dépense (`category`, `"Sans catégorie"` si absente) ; `categories` en query (CSV, sélection multiple — décision actée 2026-09-17) agrège les natures choisies en une seule série sommée, même principe que `weekly-by-category` (produits) ci-dessus.
- `GET /charts/expenses/monthly?year=` : 12 mois de l'année demandée.
- `GET /charts/expenses/top?from=&to=` : classement des natures de dépenses par montant total, plafonné à 10 comme les autres classements de ce module (`groupBy` toujours `"category"` ici, pas de branche `"product"` possible).

Les réponses reprennent exactement les mêmes formes que Recettes/Bénéfices (`WeeklyChart`/`MonthlyChart`/`RankingChart`) — aucun nouveau modèle Dart n'a donc été nécessaire côté Flutter, seulement 4 nouvelles méthodes sur `ChartsRepository`.

**Suit le filtre Année** de `GraphiquesPage` (contrairement à Stock) : une dépense a une date précise, comme une vente, donc une vue annuelle a un sens métier direct ici.

## Frontend Flutter (`lib/charts/`)

- `graphiques_page.dart` : page du module, filtre **Année** global (affecte Recettes, Bénéfices et Dépenses ; pas Stock — voir plus haut), `TabBar` Recettes/Bénéfices/Stock/Dépenses.
- `metric_charts_tab.dart` : les 5 graphiques d'un sous-module — un seul widget paramétré par `metric`/`titles`/`palette`, utilisé deux fois (Recettes et Bénéfices) plutôt que dupliqué, puisque la structure est rigoureusement identique. Chaque changement d'année recrée l'onglet via une `ValueKey('<prefix>-<year>')` plutôt qu'un `didUpdateWidget` — plus simple et réinitialise proprement filtres/semaine/mois du Top en même temps.
- `weekly_bar_chart.dart`, `monthly_line_chart.dart`, `ranking_bar_chart.dart` : widgets de rendu réutilisés par les deux sous-modules, chacun coloré via `baseColor`/`color` — une couleur différente par graphique, comme demandé (bleu/sarcelle/indigo/vert/orangé pour Recettes, violet/rose/marron/ambre/cyan pour Bénéfices). Une seule série : `baseColor` telle quelle. Plusieurs séries (catégories/produits non filtrés) : `WeeklyBarChartWidget._categoricalPalette`, une palette qualitative à 12 teintes bien distinctes (revue 2026-09-17 — l'ancienne approche « nuancer `baseColor` vers le noir » donnait des barres visuellement quasi identiques dès 4-5 catégories, constaté par l'utilisateur).
- Le classement ("Top") est rendu en barres **horizontales** plutôt que verticales : c'est le seul des 5 graphiques que la demande ne décrit pas explicitement comme "histogrammes verticaux", et une liste classée de noms de longueur variable reste plus lisible ainsi.
- **Total hebdomadaire affiché en tête de graphique** (`WeekTotalBadge`, `weekly_bar_chart.dart`, décision actée 2026-09-17, étendue à "journalières totales par produit" le 2026-09-24) : en haut à droite des cartes "journalières totales", "journalières totales par catégorie" et "journalières totales par produit" (Recettes, Bénéfices, Dépenses) — calcul purement client (`WeeklyChart.total`, somme de tous les points de toutes les séries déjà reçues, y compris après fusion multi-semaines), aucune route dédiée nécessaire.
- Filtre catégorie (graphiques 2/7, et désormais Dépenses) : `FilterChip` à **sélection multiple** ("Toutes" + une puce par catégorie/nature), rechargé via `CatalogRepository.listCategories()` ou `kPredefinedExpenseCategories` selon le sous-module — sélection vide = "Toutes" (une série par catégorie) ; une ou plusieurs sélectionnées = une seule série sommée. Filtre produit (graphiques 3/8) : liste déroulante de produits individuels (pas d'option "tous", pour éviter un histogramme à dizaines de séries illisible), défaut au premier produit du catalogue.
- Nouvelle dépendance : **`fl_chart`** (histogrammes + courbes), seule bibliothèque de graphiques Flutter significativement utilisée qui ne dépend d'aucun canal de plateforme natif (fonctionne donc sur Flutter Web) et reste activement maintenue.
- `stock_lots_tab.dart` : sous-module Stock — plus de filtre Produit séparé (retiré 2026-09-17) : un seul filtre Catégorie à **sélection multiple** (`FilterChip`, "Toutes" = réinitialisation = tout le catalogue), pilotant directement l'ensemble des produits dont les lots sont affichés. Bascule « Lots actifs (N) | Historique (N) » (un `InkWell` à indicateur de soulignement plutôt qu'un vrai `TabBar` imbriqué, plus simple pour deux options), `DataTable` des lots (colonnes Lot / [Produit, si plusieurs sélectionnés] / Date réception / Quantité reçue / Consommé / **Perdu** / Restant / Statut) et carte de synthèse du total. Sous le tableau, une seconde carte « Top des produits épuisés » (`GET /charts/out-of-stock-products`), indépendante de la sélection ci-dessus. Palette dédiée à dominante vert, délibérément distincte du bleu/violet de Recettes/Bénéfices, comme demandé dans la maquette de référence (rouge pour la carte rupture). Le lien « Voir tous les lots → » bascule simplement vers l'onglet Historique (pas d'écran séparé — cette maquette ne couvre qu'une fiche produit).
- `stock_movement_dialog.dart` (`lib/stock/`, hors module Graphiques) : le formulaire de saisie manuelle de mouvement de stock affiche désormais un champ **N° de marché** obligatoire quand le type est `'in'` et que le produit appartient à une catégorie à prix variable — reflète côté UI la contrainte serveur de `StockMovementsService.create` (voir ci-dessus).
- `expense_charts_tab.dart` : sous-module Dépenses — 4 cartes (pas 5, voir plus haut), filtre catégorie (`FilterChip` multi-sélection depuis 2026-09-17, voir plus haut) limité aux 8 natures prédéfinies (`kPredefinedExpenseCategories`, `lib/expenses/expense_models.dart`) plutôt qu'aux catégories réellement présentes en base, pour rester cohérent avec le menu déroulant du formulaire de saisie. Palette dédiée à dominante rouge/bordeaux (sortie d'argent), délibérément distincte des trois autres sous-modules.

## Vérifications effectuées

- `ChartsService` : 49 tests (Prisma mocké, sans mock pour la logique de bucketing/lots elle-même) — dont `activeStockListing`/`activeStockListingPdf` (8 tests, colonnes Prix d'achat/Recette/Bénéfice, exclusion `hasVariablePricing`, filtre `categoryIds`) et `mealsProfitListing`/`mealsProfitListingPdf` (3 tests, dont le PDF relu via `pdf-parse`) — bucketing par jour de semaine (lundi en premier, contrairement à `Date.getDay()`), résolution du lundi à partir de n'importe quel jour de la semaine visée, calcul du bénéfice (marge brute), filtrage/tri par catégorie et par produit, bucketing mensuel, classement plafonné à 10 avec le bon regroupement selon `metric`, bucketing/regroupement/classement des dépenses (mêmes garanties que Recettes/Bénéfices, dont l'agrégation multi-catégories du 2026-09-17), **répartition pro-rata de la dépense « Marché »** (3 tests), **bénéfice net de la vue "Total"** (6 tests : `revenue` non affecté, nature à cycle court déduite à sa date réelle, perte déduite à sa date réelle, nature à cycle long étalée à parts égales sur la semaine, absence de double-comptage de « Marché », amortissement d'une nature à cycle annuel sur 12 mois), **`stockLots`** (6 tests, revus 2026-09-17 : 404 produit hors établissement, **gating par produit selon sa propre catégorie sur une sélection multi-catégories** (remplace l'ancien test de rejet), renumérotation + masquage d'un lot sans commande correspondante, fusion de plusieurs produits d'une même catégorie, `lossQuantity` distincte du reste de la consommation, liste vide sans requête `Purchase` inutile), **`outOfStockProducts`** (1 test : tri alphabétique, catégorie absente → "Sans catégorie").
- `computeFifoLots` (`stock-lots.spec.ts`) : 11 tests, dont l'exemple chiffré exact de la maquette de référence (L001 épuisé, L002/L003 actifs, total 200) — ordre FIFO sur plusieurs lots, tri chronologique d'une entrée désordonnée, ajustements positif/négatif/neutre, numérotation séquentielle des lots, **parsing du N° de commande/marché depuis le motif** (`referenceNumber`), **répartition d'une perte sur un ou plusieurs lots** (`lossQuantity`, distincte du reste de la consommation).
- UI Flutter (`lib/charts/`, `lib/stock/`) : `flutter analyze` ✅ (0 issue), `flutter test` ✅ (186/186). `WeeklyChart.total` (2 tests, `chart_models_test.dart`) : somme de tous les points de toutes les séries, zéro pour une liste de séries vide. `graphiques_page_test.dart` (2026-09-17) : le filtre catégorie Dépenses est bien un `FilterChip` multi-sélection avec un chip "Toutes" ; (2026-09-25) bouton "Repas" visible sur Bénéfices seulement, carte "Recettes des semaines" visible sur Recettes seulement avec "Toutes les semaines" par défaut. `chart-permissions.spec.ts`/`chart_permissions_test.dart` : 17 permissions (5+6+2+4). `flutter build web` ✅.
- **Non vérifié en conditions réelles** : round-trip HTTP complet contre l'API de production avec de vraies ventes/achats historiques — à faire à l'occasion d'une prochaine vérification en conditions réelles, comme pour la majorité des modules de ce projet avant leur premier passage en revue de production.
