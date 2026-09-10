# Rapports — Chez Yasmine

## Routes

```
GET /establishments/:establishmentId/reports/summary                       (reports.view, ?from=&to=&period=day|week|month|year)
GET /establishments/:establishmentId/reports/summary.csv                   (reports.view, mêmes paramètres)
GET /establishments/:establishmentId/reports/payment-category-breakdown    (reports.view, mêmes paramètres — voir ci-dessous)
```

`from`/`to` (ISO 8601) prennent le pas sur `period` s'ils sont fournis ; sinon `period` (par défaut `day`) est résolu par rapport à maintenant — c'est ce qui couvre les quatre périodicités demandées par le prompt maître (§34 : journalier/hebdomadaire/mensuel/annuel) sans quatre endpoints séparés.

## Indicateurs (`ReportsService.summary`)

Tout est calculé à partir des tables existantes, sans nouvelle table :

- **Chiffre d'affaires, remises, nombre de ventes** : somme sur `Sale` non annulées (`voidedAt: null`) de la période.
- **Coût des marchandises vendues (`cogs`)** et **marge brute** : `Σ SaleItem.quantity × Product.purchasePrice` **actuel**. Simplification assumée : `SaleItem` ne fige pas un coût historique au moment de la vente (seul `unitPrice`, le prix de vente, est figé) — un changement de prix d'achat après-coup fausse légèrement la marge des périodes passées. Acceptable pour un MVP, à corriger un jour en ajoutant un `costPrice` à `SaleItem` si la précision devient critique. Pour un produit d'une catégorie à prix variable (`Category.hasVariablePricing`, ex. Poulets/Poissons/Plats africains — voir `docs/api/catalog.md`), `purchasePrice` est toujours `null` → contribue 0 au coût ici, volontairement : la dépense journalière « Marché » (`docs/api/expenses.md`) est bien déduite du bénéfice net global (`netProfit`), à plat comme toute autre dépense d'établissement — ce total-là est donc exact. Sa ventilation *par produit* (`cogs`, `productProfitability` ci-dessous), en revanche, reste 0 pour ces catégories dans ce module : la répartition pro-rata au chiffre d'affaires du jour n'est appliquée que dans le module **Graphiques** (`ChartsService.soldLines`, voir `docs/api/charts.md`), pas ici — choix délibéré, `netProfit` n'en ayant pas besoin pour rester correct.
- **Dépenses, pertes** : sommes sur `Expense`/`Loss` (cette dernière valorisée comme dans `LossesService.list`, Phase 12) de la période.
- **Bénéfice net (estimé)** : `marge brute − dépenses − pertes`.
- **Créances clients (`receivables`)** : somme de `Customer.creditBalance` — **contrairement à tous les autres indicateurs, ce n'est pas borné à la période** : c'est un solde présent, pas un flux. Documenté plutôt que mélangé silencieusement avec les indicateurs de flux.
- **Alertes de stock bas** : réutilise `StockMovementsService.listLowStockAlerts` (Phase 6) tel quel.
- **Produits les plus vendus** : agrégation en mémoire des `SaleItem` de la période par produit (quantité, chiffre d'affaires), triée décroissant, top 5.
- **Bénéfice par produit (`productProfitability`)** : même agrégation par produit, complétée du coût (`quantité × prix d'achat actuel`) et du bénéfice (`chiffre d'affaires − coût`), pour **tous** les produits vendus sur la période (pas limité à 5), triée par bénéfice décroissant. Partage la même simplification que `cogs` ci-dessus : le prix d'achat utilisé est celui du produit *aujourd'hui*, pas celui en vigueur au moment de chaque vente historique — un changement de prix d'achat fausse donc légèrement le bénéfice affiché pour les périodes passées, exactement comme pour la marge brute globale.
- **Performance des serveurs** : ventes agrégées par `Sale.createdBy` (total, nombre de ventes), avec le nom depuis `UserProfile.fullName`. Le prompt maître mentionne aussi des « commissions » (table `ServerCommission`, Phase 3) — elle existe dans le schéma mais rien ne l'alimente nulle part dans le code (aucune phase précédente n'y a jamais écrit) ; la performance ici se base donc sur les ventes réelles, pas sur des commissions qui n'existent pas encore en pratique.

## Ventilation Espèces/Mobile Money × Boissons/Plats (`ReportsService.paymentCategoryBreakdown`, décision actée 2026-09-10)

Alimente les cartes de l'écran Accueil (`lib/home/home_dashboard.dart`), toujours appelée sans paramètre donc résolue sur **aujourd'hui** (même défaut `period=day` que `summary`) :

- **Boissons** = catégories `hasCasePricing` (Bières, Vins, Sucreries) ; **Plats** = catégories `hasVariablePricing` (Poulets, Poissons, Plats africains) — voir `docs/api/catalog.md`. Chiffre d'affaires ligne à ligne (`SaleItem.quantity × SaleItem.unitPrice`), **jamais réduit par une remise** — même convention que `ChartsService` (`docs/api/charts.md`), volontairement différente de `revenue` ci-dessus (`Sale.total`, net de remise).
- **Espèces/Mobile Money** (`cashRevenue`/`mobileMoneyRevenue`) : somme de `Payment.amount` par méthode — reflète l'argent réellement encaissé, donc net de remise. `totalRevenue` est construit comme leur somme exacte (jamais un troisième chiffre indépendant) : sur une vente avec remise, `boissonsRevenue + platsRevenue` peut donc légèrement différer de `totalRevenue`, choix délibéré de cohérence interne plutôt qu'un alignement strict entre les deux.
- **Croisement catégorie × mode de paiement** (`boissonsCash`, `boissonsMobileMoney`, `platsCash`, `platsMobileMoney`) : chaque vente répartit son chiffre d'affaires Boissons/Plats au prorata de sa propre part Espèces/Mobile Money — même principe de répartition proportionnelle que l'allocation du coût « Marché » dans `ChartsService`. Une vente payée en partie Carte/Crédit (anciennes données — ces méthodes ne sont plus sélectionnables en Caisse depuis le 2026-09-10) ne compte dans aucun des deux totaux demandés.

## Exports

Le prompt maître (§34) demande PDF/Excel/CSV. Seul le **CSV** est livré (`GET .../summary.csv`, un indicateur par ligne, plus une ligne « Bénéfice — <produit> » par produit vendu sur la période) — sans dépendance supplémentaire, entièrement testable en pur TypeScript. PDF et Excel sont délibérément **reportés** : les deux demandent une vraie bibliothèque de rendu, non encore choisie ni testée — les ajouter maintenant aurait été une fonctionnalité non vérifiable plutôt qu'un vrai livrable.

## UI Flutter — tableau de bord (refonte 2026-09-10, « Interface Rapport.docx »)

`ReportsPage` (`lib/reports/reports_page.dart`) est passé d'une liste verticale plate d'indicateurs à un tableau de bord hiérarchisé, **sans aucun changement fonctionnel côté serveur** (décision explicite de l'utilisateur — refonte purement visuelle) : chaque section ci-dessous provient de champs déjà exposés par `ReportsService.summary`, à l'exception de deux compléments qui réutilisent des routes **déjà existantes** plutôt que d'en créer :

1. **Niveau 1 — Performance** : 4 cartes CA / Bénéfice net / Ventes / Panier moyen (`revenue / salesCount`, calculé côté client — pas un nouveau champ). Chacune affiche une variation par rapport à **la période équivalente précédente**, obtenue en rappelant `GET .../reports/summary` une seconde fois avec un `from`/`to` explicite (même durée que la période choisie, immédiatement avant) — ces deux paramètres étaient déjà acceptés par la route (`ReportQueryDto`), seule `ReportsRepository.getSummary` ne les exposait pas encore côté Flutter. Cette comparaison est un simple complément d'affichage : un échec (page hors-ligne, etc.) laisse `previous == null` et masque juste la variation, sans jamais bloquer l'affichage du reste de la page.
2. **Niveau 2 — Rentabilité (établissement)** : marge brute / dépenses / pertes / créances, en mini-cartes.
3. **Niveau 3 — Évolution** : réutilise tel quel le graphique hebdomadaire des recettes déjà construit pour le module Graphiques (`ChartsRepository.getWeekly(metric: 'revenue')` + `WeeklyBarChartWidget`, `docs/api/charts.md`) — affiché quelle que soit la période choisie dans Rapports (toujours la semaine en cours). Un vrai graphique heure par heure pour la période « Jour », comme esquissé dans le document de recommandation, demanderait un découpage horaire côté serveur qui n'existe nulle part dans l'application — délibérément hors périmètre de cette refonte visuelle.
4. **Niveau 4 — Analyse** : « Produits les plus vendus » (`topProducts`, médaillés 🥇🥈🥉) et « Rentabilité des produits » (`productProfitability`, avec une barre proportionnelle à la marge) — mêmes données qu'avant, présentation enrichie.
5. **Niveau 5 — Performance des serveurs** : même agrégation (`serverPerformance`), présentée en tableau avec panier moyen par serveur (calculé côté client).
6. **Niveau 6 — Points d'attention** : alerte stock (`lowStockCount`), créances (`receivables`) et pertes (`losses`) de la période, chacune avec un lien direct vers le module concerné (Stock/Clients/Pertes) quand elle est non nulle — sinon un message « Aucune alerte ». Le document de recommandation distingue « ruptures » et « stocks sous le seuil » séparément : cette distinction demanderait d'exposer la liste détaillée de `StockMovementsService.listLowStockAlerts` (actuellement seul son décompte `lowStockCount` est renvoyé par `summary`) — non fait ici pour rester strictement dans le périmètre « aucun changement fonctionnel ».

Le sélecteur Jour/Semaine/Mois/Année (`SegmentedButton<String>`) reste **en dehors** du `FutureBuilder` du contenu, comme avant la refonte — il doit rester visible et cliquable même si le chargement échoue (voir la section suivante sur le piège de test lié à ce même écran).

Délibérément **non repris** de la recommandation (fonctionnalité nouvelle, hors périmètre de cette tâche) : export PDF/Excel/impression/partage, listing exportable des ventes par serveur et des commandes d'achat par fournisseur (§12 du document), navigation « jour précédent/suivant » dans le sélecteur de période.

## Découverte en écrivant les tests : une réaction non gérée dans les widgets Flutter à rechargement

En testant le sélecteur de période de `ReportsPage`, un défaut latent — présent depuis que ce genre d'écran existe (`_reload()` dans `CustomersPage`, `ExpensesPage`, `StockPage`, etc., Phases 5-12) — s'est manifesté pour la première fois : `flutter_test` répond à tout appel HTTP réel par un faux 400 quasi instantané (`HttpOverrides` du framework, prévu pour empêcher les tests de dépendre du réseau). Si le `Future` réassigné dans un `setState(() { _future = repo.methode(); })` rejette avant que `FutureBuilder` ne se réabonne au prochain rebuild, Dart le signale comme une erreur non gérée — même si `FutureBuilder` l'aurait normalement affichée proprement. En production, un vrai appel réseau prend toujours assez de temps pour que cette course n'ait pas d'effet observable ; ce n'est donc pas un bug de production, seulement un piège de test resté invisible faute d'un test qui déclenche un rechargement puis attend son résultat.

Corrigé dans `ReportsPage._changePeriod` avec `future.ignore()` (l'API Dart prévue exactement pour ce cas), qui marque le futur comme observé sans changer ce que `FutureBuilder` reçoit. **Pas répercuté** dans les autres écrans à rechargement (`CustomersPage`, `ExpensesPage`, `LossesPage`, `CashPage`, `StockPage`, etc.) : c'est un artefact d'environnement de test, pas un bug métier, et aucun de leurs tests actuels ne l'exerce — corriger douze fichiers déjà livrés et testés pour un scénario de test non écrit aurait été hors de proportion avec cette phase. Noté ici pour mémoire si un futur test venait à l'exercer ailleurs.

## Vérifications effectuées

- `ReportsService.resolveRange` : 3 tests (from/to prioritaire, défaut « jour », résolution « mois »).
- `ReportsService.summary` : 5 tests (Prisma mocké) — exclusion des ventes annulées et filtrage établissement/période, calcul chiffre d'affaires/marge/bénéfice net, classement des produits les plus vendus, **bénéfice par produit non plafonné trié par bénéfice décroissant**, agrégation par serveur.
- `ReportsService.summaryCsv` : 1 test — en-tête et au moins un indicateur présents.
- `ReportsService.paymentCategoryBreakdown` : 3 tests — somme Espèces/Mobile Money et Boissons/Plats, répartition proportionnelle d'une vente à paiement mixte, exclusion Carte/Crédit des deux totaux demandés.
- UI Flutter (`lib/reports/`) : sélecteur de période toujours visible (y compris en cas d'échec de chargement), export CSV affiché dans un dialogue (copiable), et — comme détaillé ci-dessus — un test qui exerce spécifiquement le changement de période jusqu'à son rechargement complet. `flutter analyze`/`test`/`build web` ✅ (42/42 tests Flutter, y compris les 2 tests dédiés à `ReportsPage` inchangés par la refonte visuelle).
- **Vérifié en conditions réelles** (2026-09-06, avant l'ajout du bénéfice par produit) : round-trip complet navigateur → API de production → base réelle, avec de vraies ventes/dépenses/pertes, voir `PROJECT_PLAN.md` — le bénéfice par produit lui-même repose sur la même requête déjà vérifiée, non rejoué en conditions réelles séparément après son ajout.
