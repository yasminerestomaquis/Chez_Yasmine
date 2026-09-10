# Graphiques — Chez Yasmine

## Routes

Toutes protégées par `SupabaseJwtGuard` + `PermissionsGuard` + `@RequirePermissions('reports.view')` — même permission que le module Rapports, puisqu'il s'agit de la même donnée métier, seulement visualisée différemment.

```
GET /establishments/:establishmentId/charts/weekly?metric=revenue|profit&weekStart=YYYY-MM-DD
GET /establishments/:establishmentId/charts/weekly-by-category?metric=&weekStart=&categoryId=
GET /establishments/:establishmentId/charts/weekly-by-product?metric=&weekStart=&productId=
GET /establishments/:establishmentId/charts/monthly?metric=revenue|profit&year=YYYY
GET /establishments/:establishmentId/charts/top?metric=revenue|profit&from=&to=
GET /establishments/:establishmentId/charts/stock-lots?productId=
GET /establishments/:establishmentId/charts/expenses/weekly?weekStart=YYYY-MM-DD
GET /establishments/:establishmentId/charts/expenses/weekly-by-category?weekStart=&category=
GET /establishments/:establishmentId/charts/expenses/monthly?year=YYYY
GET /establishments/:establishmentId/charts/expenses/top?from=&to=
```

`metric` est obligatoire sur les routes Recettes/Bénéfices : `revenue` ou `profit`. `stock-lots` et les routes `expenses/*` n'ont pas de `metric` — une seule grandeur possible dans chaque cas (voir leurs sections dédiées).

## Définitions retenues (à lire avant toute autre chose)

- **Recettes** = chiffre d'affaires ligne à ligne (`SaleItem.quantity × SaleItem.unitPrice`), jamais réduit par une remise (les remises ne sont enregistrées qu'au niveau de la vente entière, pas par ligne, voir `docs/api/pos.md`). Même le graphique "total" sans filtre additionne ces lignes plutôt que `Sale.total`, précisément pour que la somme des graphiques par catégorie/par produit reconcilie toujours avec le total journalier. Conséquence assumée : ce total peut légèrement différer du "chiffre d'affaires" affiché dans le module **Rapports** (qui utilise `Sale.total`, net de remise) — un choix de cohérence interne à ce module plutôt qu'un alignement strict avec Rapports.
- **Bénéfices** = marge brute (`revenue − coût`), **jamais** le bénéfice net après dépenses/pertes du module Rapports. Les dépenses et les pertes ne sont pas rattachées à un produit ou une catégorie ; il n'existe donc aucune façon correcte de les répartir dans un graphique par catégorie/produit/jour — **sauf exception documentée ci-dessous pour Poulets/Poissons/Plats africains**. Pour toute autre catégorie, le coût utilisé est `quantité × prix d'achat actuel du produit` (même simplification que `productProfitability`/`cogs` côté Rapports : le prix d'achat utilisé est celui du produit *aujourd'hui*, pas celui en vigueur au moment de chaque vente historique).

## Coût des catégories à prix variable : répartition de la dépense « Marché » (décision actée 2026-09-10)

Poulets, Poissons, Plats africains (`Category.hasVariablePricing`) n'ont jamais de `Product.purchasePrice` (leur prix d'achat varie trop d'un jour à l'autre pour qu'une valeur figée sur la fiche produit soit fiable — voir `docs/api/purchasing.md`). Sans correction, `effectiveUnitCost()` renverrait 0 pour ces produits et gonflerait artificiellement leur bénéfice affiché dans ce module.

`ChartsService.soldLines()` corrige cela en une seule fois, en aval de `effectiveUnitCost()`, pour que les 5 graphiques Bénéfices (`weeklyTotal`, `weeklyByCategory`, `weeklyByProduct`, `monthly`, `top`) en héritent automatiquement sans logique dupliquée :

1. Pour chaque **jour civil** (heure locale, même convention que `weekdayIndex`/`mondayOf`) de la période demandée, additionner le montant des dépenses de nature **« Marché »** (`Expense.category`, `Expense.expenseDate`) enregistrées ce jour-là.
2. Répartir ce total entre les lignes de vente de ce même jour appartenant à une catégorie `hasVariablePricing`, **au prorata du chiffre d'affaires de chaque ligne** ce jour-là (`ligne.revenue / Σ revenue du jour pour ces catégories`).
3. Le coût ainsi calculé remplace celui de `effectiveUnitCost()` pour ces lignes uniquement — les catégories à prix fixe/par casier ne sont jamais concernées.

**Cas limite assumé** : un jour avec des ventes Poulets/Poissons/Plats africains mais **aucune** dépense « Marché » saisie ce jour-là a un coût alloué de **0** pour ce jour (bénéfice apparent = 100% du chiffre d'affaires) — c'est un signal qu'il manque une saisie, pas une erreur de calcul. D'où l'ajout d'un champ Date dans le formulaire de saisie de dépense (`docs/api/expenses.md`), pour permettre de saisir la dépense Marché un autre jour que "aujourd'hui" (après coup, ou en avance).

**Délibérément limité à `ChartsService`, pas répercuté dans `ReportsService`** : le bénéfice net global de Rapports (`netProfit`) est déjà exact, la dépense Marché y étant déjà déduite en tant que dépense d'établissement à plat — seule sa ventilation *par produit* (`productProfitability`), non utilisée ici, resterait imprécise pour ces 3 catégories. Corriger uniquement ce sous-module aurait dupliqué la même logique d'allocation sans bénéfice pour l'indicateur global déjà correct (voir `docs/api/reports.md`).

**Choix historique abandonné** : un essai antérieur a étendu le module Achats à ces catégories pour y figer un "dernier prix d'achat connu" sur `Product.purchasePrice` — abandonné sur décision explicite de l'utilisateur (2026-09-10), ce prix variant trop d'un jour à l'autre pour ne pas fausser rétroactivement le bénéfice des jours précédant le dernier achat enregistré. Voir `docs/api/purchasing.md`.

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
- `GET /charts/weekly-by-product` : même principe, une série par produit vendu (ou une seule avec `productId`).

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

## Sous-module Stock — lots FIFO (`GET /charts/stock-lots?productId=`)

Maquette demandée pour une fiche de gestion de stock par lots (First In, First Out) : quelle part du stock actuel d'un produit provient de quelle livraison. Aucun schéma dédié — reconstruit à la volée depuis l'historique existant des `StockMovement` (`apps/api/nestjs/src/stock/`), le même que celui qui alimente `product.stockQuantity` :

- Chaque mouvement `'in'` (réception d'achat via `PurchasesService.receive`, ou remboursement de vente via `SalesService.refund`) devient un **lot** indépendant, daté de `StockMovement.createdAt`, avec sa propre quantité restante.
- Chaque mouvement de sortie (`'out'`, `'sale'`, `'loss'`) est imputé aux lots existants **du plus ancien au plus récent** (FIFO) — un lot atteignant 0 restant devient `epuise` et disparaît des lots actifs, mais reste dans l'historique complet (traçabilité).
- `'adjustment'` (quantité absolue, pas relative — voir `stock-math.ts`) est traité comme la différence avec le total couru : une hausse crée un lot synthétique daté de l'ajustement, une baisse consomme les lots existants en FIFO. Cela préserve l'invariant « somme des restants des lots actifs == `product.stockQuantity` » même avec des corrections manuelles.
- La logique pure (aucun accès DB) vit dans `apps/api/nestjs/src/stock/stock-lots.ts` (`computeFifoLots`), testée isolément puis appelée par `ChartsService.stockLots` qui se contente de charger les mouvements du produit triés par date et de vérifier son appartenance à l'établissement.

```json
{
  "productId": "...",
  "productName": "Bière Flag 65cl",
  "activeLots": [
    { "code": "L002", "receivedAt": "2025-09-05T08:00:00.000Z", "receivedQuantity": 150, "consumedQuantity": 70, "remainingQuantity": 80, "status": "actif" },
    { "code": "L003", "receivedAt": "2025-09-10T08:00:00.000Z", "receivedQuantity": 120, "consumedQuantity": 0, "remainingQuantity": 120, "status": "actif" }
  ],
  "historyLots": ["... les 3 lots, y compris L001 (épuisé)"],
  "totalActiveUnits": 200
}
```

`activeLots` alimente l'onglet « Lots actifs (N) », `historyLots` (tous les lots, tous statuts confondus) l'onglet « Historique (N) », `totalActiveUnits` la carte de synthèse — exclusivement la somme des restants des lots **actifs**, jamais affecté par l'onglet actuellement affiché.

**Divergence assumée avec le reste du module** : cette vue n'est PAS bornée par le filtre Année de `GraphiquesPage` — elle prend tout l'historique du produit, parce qu'elle représente l'état *courant* du stock, pas une période. Un lot reçu il y a plusieurs années peut rester actif aujourd'hui ; y appliquer un filtre Année casserait la lecture du stock réellement disponible.

## Sous-module Dépenses — 4 graphiques, pas 5 (`GET /charts/expenses/*`)

Décision explicite de l'utilisateur (2026-09-08) : plutôt que de forcer les dépenses dans les graphiques Recettes/Bénéfices existants (une dépense n'a ni produit ni catégorie de *produit* — seulement sa propre nature, Loyer/Eau/... voir `docs/api/expenses.md`), un sous-module séparé les regroupe. Il compte **4** graphiques, pas 5 : pas de "par produit", une dépense n'étant rattachée à aucun produit.

- `GET /charts/expenses/weekly` : total journalier (Lundi→Dimanche d'une semaine choisie), même résolution du lundi que les routes `weekly` existantes (`weekRange`/`buildWeekResponse` réutilisées telles quelles).
- `GET /charts/expenses/weekly-by-category` : idem, ventilé par nature de dépense (`category`, `"Sans catégorie"` si absente) ; `category` en query filtre à une seule nature.
- `GET /charts/expenses/monthly?year=` : 12 mois de l'année demandée.
- `GET /charts/expenses/top?from=&to=` : classement des natures de dépenses par montant total, plafonné à 10 comme les autres classements de ce module (`groupBy` toujours `"category"` ici, pas de branche `"product"` possible).

Les réponses reprennent exactement les mêmes formes que Recettes/Bénéfices (`WeeklyChart`/`MonthlyChart`/`RankingChart`) — aucun nouveau modèle Dart n'a donc été nécessaire côté Flutter, seulement 4 nouvelles méthodes sur `ChartsRepository`.

**Suit le filtre Année** de `GraphiquesPage` (contrairement à Stock) : une dépense a une date précise, comme une vente, donc une vue annuelle a un sens métier direct ici.

## Frontend Flutter (`lib/charts/`)

- `graphiques_page.dart` : page du module, filtre **Année** global (affecte Recettes, Bénéfices et Dépenses ; pas Stock — voir plus haut), `TabBar` Recettes/Bénéfices/Stock/Dépenses.
- `metric_charts_tab.dart` : les 5 graphiques d'un sous-module — un seul widget paramétré par `metric`/`titles`/`palette`, utilisé deux fois (Recettes et Bénéfices) plutôt que dupliqué, puisque la structure est rigoureusement identique. Chaque changement d'année recrée l'onglet via une `ValueKey('<prefix>-<year>')` plutôt qu'un `didUpdateWidget` — plus simple et réinitialise proprement filtres/semaine/mois du Top en même temps.
- `weekly_bar_chart.dart`, `monthly_line_chart.dart`, `ranking_bar_chart.dart` : widgets de rendu réutilisés par les deux sous-modules, chacun coloré via `baseColor`/`color` — une couleur différente par graphique, comme demandé (bleu/sarcelle/indigo/vert/orangé pour Recettes, violet/rose/marron/ambre/cyan pour Bénéfices). Quand un graphique affiche plusieurs séries (catégories/produits non filtrés), chaque série reprend une nuance de la couleur du graphique plutôt qu'une palette sans rapport.
- Le classement ("Top") est rendu en barres **horizontales** plutôt que verticales : c'est le seul des 5 graphiques que la demande ne décrit pas explicitement comme "histogrammes verticaux", et une liste classée de noms de longueur variable reste plus lisible ainsi.
- Filtre catégorie (graphiques 2/7) : liste déroulante "Toutes les catégories" + chaque catégorie, rechargée via `CatalogRepository.listCategories()` déjà existant. Filtre produit (graphiques 3/8) : liste déroulante de produits individuels (pas d'option "tous", pour éviter un histogramme à dizaines de séries illisible), défaut au premier produit du catalogue.
- Nouvelle dépendance : **`fl_chart`** (histogrammes + courbes), seule bibliothèque de graphiques Flutter significativement utilisée qui ne dépend d'aucun canal de plateforme natif (fonctionne donc sur Flutter Web) et reste activement maintenue.
- `stock_lots_tab.dart` : sous-module Stock — sélecteur de produit, bascule « Lots actifs (N) | Historique (N) » (un `InkWell` à indicateur de soulignement plutôt qu'un vrai `TabBar` imbriqué, plus simple pour deux options), `DataTable` des lots (colonnes Lot / Date réception / Quantité reçue / Consommé / Restant / Statut) et carte de synthèse du total. Palette dédiée à dominante vert, délibérément distincte du bleu/violet de Recettes/Bénéfices, comme demandé dans la maquette de référence. Le lien « Voir tous les lots → » bascule simplement vers l'onglet Historique (pas d'écran séparé — cette maquette ne couvre qu'une fiche produit).
- `expense_charts_tab.dart` : sous-module Dépenses — 4 cartes (pas 5, voir plus haut), filtre catégorie limité aux 8 natures prédéfinies (`kPredefinedExpenseCategories`, `lib/expenses/expense_models.dart`) plutôt qu'aux catégories réellement présentes en base, pour rester cohérent avec le menu déroulant du formulaire de saisie. Palette dédiée à dominante rouge/bordeaux (sortie d'argent), délibérément distincte des trois autres sous-modules.

## Vérifications effectuées

- `ChartsService` : 23 tests (Prisma mocké, sans mock pour la logique de bucketing/lots elle-même) — bucketing par jour de semaine (lundi en premier, contrairement à `Date.getDay()`), résolution du lundi à partir de n'importe quel jour de la semaine visée, calcul du bénéfice (marge brute), filtrage/tri par catégorie et par produit, bucketing mensuel, classement plafonné à 10 avec le bon regroupement selon `metric`, reconstruction des lots FIFO (dont un cas 404 produit hors établissement), bucketing/regroupement/classement des dépenses (mêmes garanties que Recettes/Bénéfices), **répartition pro-rata de la dépense « Marché »** (3 tests : allocation correcte entre plusieurs lignes le même jour, coût à 0 un jour sans dépense « Marché » saisie, aucune requête `Expense` déclenchée si aucune ligne vendue n'appartient à une catégorie à prix variable).
- `computeFifoLots` (`stock-lots.spec.ts`) : 8 tests, dont l'exemple chiffré exact de la maquette de référence (L001 épuisé, L002/L003 actifs, total 200) — ordre FIFO sur plusieurs lots, tri chronologique d'une entrée désordonnée, ajustements positif/négatif/neutre, numérotation séquentielle des lots.
- UI Flutter (`lib/charts/`) : `flutter analyze` ✅ (0 issue), 6 tests widget — affichage des 5 titres de chaque sous-module sans erreur non gérée, bascule d'onglet, changement d'année (recrée les onglets sans crash), bascule vers l'onglet Stock (en-tête + état "aucun produit" sans backend en test), bascule vers l'onglet Dépenses (4 titres, absence de "par produit"), filtre catégorie du sous-module Dépenses. `flutter build web` ✅.
- **Non vérifié en conditions réelles** : round-trip HTTP complet contre l'API de production avec de vraies ventes/achats historiques — à faire à l'occasion d'une prochaine vérification en conditions réelles, comme pour la majorité des modules de ce projet avant leur premier passage en revue de production.
