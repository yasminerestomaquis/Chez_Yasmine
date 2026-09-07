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
```

`metric` est obligatoire partout où il apparaît : `revenue` pour les graphiques "Recettes", `profit` pour "Bénéfices". `stock-lots` n'a pas de `metric` — voir la section dédiée, ce n'est pas un graphique Recettes/Bénéfices.

## Définitions retenues (à lire avant toute autre chose)

- **Recettes** = chiffre d'affaires ligne à ligne (`SaleItem.quantity × SaleItem.unitPrice`), jamais réduit par une remise (les remises ne sont enregistrées qu'au niveau de la vente entière, pas par ligne, voir `docs/api/pos.md`). Même le graphique "total" sans filtre additionne ces lignes plutôt que `Sale.total`, précisément pour que la somme des graphiques par catégorie/par produit reconcilie toujours avec le total journalier. Conséquence assumée : ce total peut légèrement différer du "chiffre d'affaires" affiché dans le module **Rapports** (qui utilise `Sale.total`, net de remise) — un choix de cohérence interne à ce module plutôt qu'un alignement strict avec Rapports.
- **Bénéfices** = marge brute (`revenue − quantité × prix d'achat actuel du produit`), **jamais** le bénéfice net après dépenses/pertes du module Rapports. Les dépenses et les pertes ne sont pas rattachées à un produit ou une catégorie ; il n'existe donc aucune façon correcte de les répartir dans un graphique par catégorie/produit/jour. Cette marge brute partage la même simplification que `productProfitability` (Rapports) et `cogs` : le prix d'achat utilisé est celui du produit *aujourd'hui*, pas celui en vigueur au moment de chaque vente historique.

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

## Frontend Flutter (`lib/charts/`)

- `graphiques_page.dart` : page du module, filtre **Année** global (affecte Recettes et Bénéfices, pas Stock — voir plus haut), `TabBar` Recettes/Bénéfices/Stock.
- `metric_charts_tab.dart` : les 5 graphiques d'un sous-module — un seul widget paramétré par `metric`/`titles`/`palette`, utilisé deux fois (Recettes et Bénéfices) plutôt que dupliqué, puisque la structure est rigoureusement identique. Chaque changement d'année recrée l'onglet via une `ValueKey('<prefix>-<year>')` plutôt qu'un `didUpdateWidget` — plus simple et réinitialise proprement filtres/semaine/mois du Top en même temps.
- `weekly_bar_chart.dart`, `monthly_line_chart.dart`, `ranking_bar_chart.dart` : widgets de rendu réutilisés par les deux sous-modules, chacun coloré via `baseColor`/`color` — une couleur différente par graphique, comme demandé (bleu/sarcelle/indigo/vert/orangé pour Recettes, violet/rose/marron/ambre/cyan pour Bénéfices). Quand un graphique affiche plusieurs séries (catégories/produits non filtrés), chaque série reprend une nuance de la couleur du graphique plutôt qu'une palette sans rapport.
- Le classement ("Top") est rendu en barres **horizontales** plutôt que verticales : c'est le seul des 5 graphiques que la demande ne décrit pas explicitement comme "histogrammes verticaux", et une liste classée de noms de longueur variable reste plus lisible ainsi.
- Filtre catégorie (graphiques 2/7) : liste déroulante "Toutes les catégories" + chaque catégorie, rechargée via `CatalogRepository.listCategories()` déjà existant. Filtre produit (graphiques 3/8) : liste déroulante de produits individuels (pas d'option "tous", pour éviter un histogramme à dizaines de séries illisible), défaut au premier produit du catalogue.
- Nouvelle dépendance : **`fl_chart`** (histogrammes + courbes), seule bibliothèque de graphiques Flutter significativement utilisée qui ne dépend d'aucun canal de plateforme natif (fonctionne donc sur Flutter Web) et reste activement maintenue.
- `stock_lots_tab.dart` : sous-module Stock — sélecteur de produit, bascule « Lots actifs (N) | Historique (N) » (un `InkWell` à indicateur de soulignement plutôt qu'un vrai `TabBar` imbriqué, plus simple pour deux options), `DataTable` des lots (colonnes Lot / Date réception / Quantité reçue / Consommé / Restant / Statut) et carte de synthèse du total. Palette dédiée à dominante vert, délibérément distincte du bleu/violet de Recettes/Bénéfices, comme demandé dans la maquette de référence. Le lien « Voir tous les lots → » bascule simplement vers l'onglet Historique (pas d'écran séparé — cette maquette ne couvre qu'une fiche produit).

## Vérifications effectuées

- `ChartsService` : 13 tests (Prisma mocké, sans mock pour la logique de bucketing/lots elle-même) — bucketing par jour de semaine (lundi en premier, contrairement à `Date.getDay()`), résolution du lundi à partir de n'importe quel jour de la semaine visée, calcul du bénéfice (marge brute), filtrage/tri par catégorie et par produit, bucketing mensuel, classement plafonné à 10 avec le bon regroupement selon `metric`, reconstruction des lots FIFO (dont un cas 404 produit hors établissement).
- `computeFifoLots` (`stock-lots.spec.ts`) : 8 tests, dont l'exemple chiffré exact de la maquette de référence (L001 épuisé, L002/L003 actifs, total 200) — ordre FIFO sur plusieurs lots, tri chronologique d'une entrée désordonnée, ajustements positif/négatif/neutre, numérotation séquentielle des lots.
- UI Flutter (`lib/charts/`) : `flutter analyze` ✅ (0 issue), 4 tests widget — affichage des 5 titres de chaque sous-module sans erreur non gérée, bascule d'onglet, changement d'année (recrée les deux onglets sans crash), bascule vers l'onglet Stock (en-tête + état "aucun produit" sans backend en test). `flutter build web` ✅.
- **Non vérifié en conditions réelles** : round-trip HTTP complet contre l'API de production avec de vraies ventes/achats historiques — à faire à l'occasion d'une prochaine vérification en conditions réelles, comme pour la majorité des modules de ce projet avant leur premier passage en revue de production.
