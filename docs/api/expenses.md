# Dépenses — Chez Yasmine

## Routes

```
GET    /establishments/:establishmentId/expenses?from=&to=            (expenses.manage)
GET    /establishments/:establishmentId/expenses/next-market-number   (expenses.manage)
GET    /establishments/:establishmentId/expenses/summary              (expenses.manage)
GET    /establishments/:establishmentId/expenses/history              (expenses.manage)
GET    /establishments/:establishmentId/expenses/history.xlsx         (expenses.manage)
POST   /establishments/:establishmentId/expenses                       (expenses.manage)
PATCH  /establishments/:establishmentId/expenses/:expenseId            (expenses.manage)
DELETE /establishments/:establishmentId/expenses/:expenseId            (expenses.manage)
```

Routes du sous-module Salaires/Paie (voir plus bas) : `docs/api/expenses.md#salaires--paie-payroll`.

## Champs

`label` (obligatoire), `category` (texte libre — voir plus bas), `amount` (obligatoire, > 0), `expenseDate` (par défaut aujourd'hui, éditable — voir ci-dessous), `periodicity` (`one_off` | `recurring`, par défaut `one_off`), `note`, `marketNumber` (entier optionnel — voir ci-dessous), `paymentMethod` (`cash` | `mobile_money`, par défaut `cash`, ajouté 2026-09-12 — voir « Historique » ci-dessous), `status` (`paid` | `pending` | `cancelled`, par défaut `paid`, ajouté 2026-09-12), `payrollRunId` (identifiant du `PayrollRun` à l'origine d'une dépense « Salaires » — voir plus bas, jamais renseignable manuellement).

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

## Refonte en 4 sous-onglets (décision actée 2026-09-12)

Sur demande explicite de l'utilisateur (fichier `Prompt Dépenses.md`), le module Dépenses (`lib/expenses/expenses_page.dart`) est réorganisé en 4 sous-onglets d'un même `Scaffold` (`DefaultTabController`, nécessaire pour que « Voir tout → » de Vue d'ensemble puisse naviguer vers Historique via `DefaultTabController.of(context).animateTo(3)`) : **Vue d'ensemble**, **Dépenses** (formulaire + liste existants, extraits verbatim dans `expenses_form_tab.dart` sans aucun changement de champ — en particulier, aucun champ « Justificatif » n'a jamais existé, rien à retirer), **Salaires** (nouveau, voir plus bas) et **Historique** (nouveau, voir plus bas). Aucune route ni aucun comportement des autres modules du projet (Rapports, Graphiques, Achats, Stock, etc.) n'a été modifié par cette refonte.

`TabBarView` garde les 4 onglets vivants en mémoire en changeant d'onglet — sans précaution, une mutation faite dans un onglet (payer une paie, ajouter/annuler une dépense) resterait invisible dans les autres jusqu'à quitter et rouvrir toute la page. `ReloadOnTabVisitMixin` (`lib/common/reload_on_tab_visit_mixin.dart`, décision actée 2026-09-13), appliqué aux 4 onglets, écoute le `TabController` et recharge automatiquement les données d'un onglet dès qu'on y navigue depuis un autre — pas besoin d'un bus de mutation explicite, la fraîcheur est garantie au moment où l'utilisateur regarde effectivement l'onglet.

### Vue d'ensemble

`GET .../expenses/summary?period=&year=&month=&weekOf=` (`ExpensesService.summary`, `expenses_overview_tab.dart`) — filtres Année/Mois/Semaine avec navigation précédent/suivant, calculés par `resolveExpensePeriodRange`/`previousRange` (mêmes fonctions pour la période affichée et la période de comparaison, garantissant que le delta % est toujours calculé sur deux plages de même durée). Renvoie 4 KPI (total des dépenses, Salaires, Marché, autres charges fixes — ce dernier calculé par soustraction du total, les 3 autres catégories étant mutuellement exclusives), **chacun avec sa propre évolution en % par rapport à la période précédente** (`changePercent`/`changePercentSalaries`/`changePercentMarket`/`changePercentFixedCharges`, chacun calculé sur la même paire de plages que le total, jamais mélangés), une série pour le graphique d'évolution, une ventilation par catégorie (alimentant le donut `expense_category_donut_chart.dart`) et les 8 dépenses les plus récentes (tous filtres de période ignorés) avec un lien « Voir tout → » vers l'onglet Historique.

### Historique

`GET .../expenses/history?period=&year=&month=&weekOf=&category=&status=&paymentMethod=&page=&pageSize=` et son pendant `GET .../expenses/history.xlsx` (mêmes paramètres de filtre, `ExpensesService.exportHistoryExcel`) — le fichier Excel exporté contient **exclusivement** les dépenses correspondant aux filtres actifs à l'écran, jamais l'intégralité de la table (garanti par construction : les deux routes partagent la même fonction `historyWhere` de construction du filtre Prisma), et affiche les mêmes libellés français que l'écran pour « Mode de paiement »/« Statut » (`ExpensesService.paymentMethodLabels`/`statusLabels`, alignés sur `ExpensePaymentMethod`/`ExpenseStatus` côté Flutter), jamais les valeurs techniques brutes stockées en base. Filtre « Période » optionnel (contrairement à Vue d'ensemble, l'Historique liste par défaut **toutes** les dépenses sans contrainte de date) ; un filtre `period=week` est valide sans `year` explicite (la semaine est encodée dans `weekOf`, format `YYYY-MM-DD` d'un jour quelconque de cette semaine).

### Mode de paiement et statut d'une dépense (décision actée 2026-09-13)

Le formulaire de création (`expenses_form_tab.dart`) laisse choisir le **mode de paiement** (Espèces/Mobile Money/Virement) et, à la création, le **statut** Payée (par défaut) ou En attente — une dépense engagée mais pas encore réglée. Le statut **Annulée** n'est jamais choisi à la création : il ne s'atteint qu'en marquant une dépense existante comme annulée (bouton dédié dans la liste, `PATCH .../expenses/:id { status: 'cancelled' }`), ce qui la conserve (contrairement à « Supprimer ») pour garder une trace d'audit. Ces deux actions (annuler, supprimer), ainsi que toute modification, sont **refusées par le serveur** (`400`) pour une dépense dont `payrollRunId` n'est pas nul — voir « Garde-fous » ci-dessous.

### Garde-fous autour de la nature « Salaires » (décision actée 2026-09-13)

Le montant d'une dépense « Salaires » ne doit jamais être saisi à la main (voir plus bas) — deux garanties, appliquées côté serveur donc valables quel que soit le client :
- `POST .../expenses` **refuse** toute création avec `category === 'Salaires'` (`ExpensesService.create`, avant même la vérification d'idempotence) — le menu déroulant du formulaire Flutter l'exclut déjà de ses choix, mais le serveur est la véritable ligne de défense (couvre aussi un contournement via l'option « Autre… »).
- `PATCH`/`DELETE .../expenses/:id` **refusent** toute modification ou suppression d'une dépense dont `payrollRunId` n'est pas nul (`ExpensesService.update`/`remove`, via `findOwnExpenseOrThrow`) — évite de désynchroniser silencieusement un `PayrollRun` déjà payé de la dépense qu'il a générée. Le bouton « Annuler »/« Supprimer » de la liste Flutter est d'ailleurs masqué pour ces lignes (`Expense.isFromPayroll`).

## Salaires / Paie (`payroll`)

Nouveau sous-module (décision actée 2026-09-12), module NestJS séparé `apps/api/nestjs/src/payroll/`, permissions dédiées `payroll.manage` (mutations) / `payroll.view` (lecture seule) — accordées uniquement à Administrateur, Comptable, Gérant, Propriétaire et Super Administrateur (jamais à Caissier, Serveur ou Magasinier, qui n'ont pas de raison métier d'accéder à la Paie).

### Routes

```
GET    /establishments/:establishmentId/employees                      (payroll.view)
POST   /establishments/:establishmentId/employees                      (payroll.manage)
PATCH  /establishments/:establishmentId/employees/:employeeId          (payroll.manage)
GET    /establishments/:establishmentId/payroll-runs                   (payroll.view)
GET    /establishments/:establishmentId/payroll-runs/dashboard         (payroll.view)
POST   /establishments/:establishmentId/payroll-runs                   (payroll.manage)   -- « préparer »
PATCH  /establishments/:establishmentId/payroll-runs/:runId/lines/:lineId  (payroll.manage) -- éditer avance/prime
POST   /establishments/:establishmentId/payroll-runs/:runId/validate   (payroll.manage)
POST   /establishments/:establishmentId/payroll-runs/:runId/pay        (payroll.manage)
POST   /establishments/:establishmentId/payroll-runs/:runId/cancel     (payroll.manage)
```

### Modèle de données

- `Employee` (`lastName`/`firstName` — pas de champ `fullName` en base, seulement un getter Flutter `Employee.fullName` — `gender`, `birthDate`, `phone` — obligatoire, regex `^0\d{9}$`, normalisé côté DTO —, `address`, `photoUrl` (toujours `null`, voir plus bas), `position`, `hireDate`, `contractType`, `weeklySalary`, `team`, `registrationNumber`, `notes`, `status` `active`/`inactive`). **Jamais de suppression physique** : un employé retiré passe en `status: 'inactive'` — via le menu « Désactiver » de chaque ligne dans l'onglet Salaires (`PATCH .../employees/:id { status: 'inactive' }`) —, ce qui l'exclut automatiquement de la prochaine préparation de paie (`PayrollService.prepare` ne sélectionne que `status: 'active'`) tout en préservant son historique de paie déjà enregistré ; réactivable à tout moment de la même façon. Tous les champs, y compris le statut, sont modifiables après création (bouton « Modifier », même formulaire que la création pré-rempli).
- `PayrollRun` (`periodStart`, `periodEnd`, `status` : `prepared` → `validated` → `paid` (ou `cancelled` depuis `prepared`/`validated`), `preparedBy`/`validatedBy`/`paidBy` → FK `UserProfile` pour l'audit). Aucune contrainte d'unicité de période côté base — la garde anti-doublon (« Paie de la semaine déjà préparée ») est appliquée côté UI Flutter (`payroll_run_page.dart`) en comparant `periodStart` au lundi courant parmi les runs non annulés.
- `PayrollLine` (`baseSalary` — snapshot de `Employee.weeklySalary` au moment de la préparation, jamais recalculé rétroactivement si le salaire de l'employé change ensuite —, `advance`, `adjustment`, `netAmount = baseSalary - advance + adjustment`), `@@unique([payrollRunId, employeeId])`.
- `Expense.payrollRunId` (`String? @unique`) : lien vers le `PayrollRun` à l'origine d'une dépense « Salaires » créée automatiquement.

### État machine et idempotence du paiement

`prepared` (éditable : avance/prime par ligne) → `validated` (figé, plus d'édition de ligne) → `paid` (déclenche la création de la dépense) ; `cancelled` accessible depuis `prepared` ou `validated` uniquement (jamais depuis `paid`, un paiement effectué est définitif). `PayrollService.pay` crée l'`Expense` (`category: 'Salaires'`, `amount` = somme des `netAmount`, `payrollRunId`) et passe le statut à `paid` **dans une seule transaction Prisma** (`$transaction([update, create])`) — garantit qu'un paiement ne peut jamais exister sans sa dépense correspondante ni l'inverse. Double ligne de défense contre un double paiement : le service applicatif refuse `pay()` si `status !== 'validated'`, **et** la contrainte `UNIQUE` sur `Expense.payrollRunId` (`expenses_payroll_run_id_key`, vérifiée en base de production) empêcherait de toute façon une deuxième dépense pour le même run même en cas de bug applicatif. Le montant de la dépense « Salaires » ainsi créée n'est **jamais saisissable manuellement** dans le formulaire Dépenses : c'est la seule nature de dépense dont le montant provient exclusivement d'un paiement de paie réel.

### Photo employé : différée (décision actée 2026-09-12)

Le formulaire employé (`employee_form_dialog.dart`) n'inclut volontairement **aucun champ d'upload de photo**, malgré ce que pourrait suggérer un module RH classique. Raison : le seul pipeline d'upload existant (`docs/api/catalog.md` § images) cible un bucket Supabase Storage `product-images` codé en dur (chemin `product-images/{organization_id}/{establishment_id}/{product_id}/{uuid}.webp`) et des policies RLS écrites spécifiquement pour ce cas d'usage — les réutiliser tel quel pour des photos d'employés exposerait potentiellement des photos RH via des règles d'accès pensées pour des images de catalogue public. Un futur bucket `employee-photos` dédié, avec ses propres policies RLS auditées, est nécessaire avant d'activer cette fonctionnalité — non fait dans cette itération, `Employee.photoUrl` existe en base (`String?`) mais reste toujours `null` en pratique.

## Vérifications effectuées

- `ExpensesService` : tests couvrant le filtrage par période, la mise à jour/suppression scopées par établissement, la valeur par défaut et la transmission de `periodicity`, le rejeu idempotent d'une création (aucun doublon, aucune notification en double), la notification de l'organisation sur une création réelle, la transmission de `marketNumber`, et `nextMarketNumber` (1 si aucune dépense « Marché », dernier + 1 sinon, scopé à `category === 'Marché'`).
- UI Flutter (`lib/expenses/`) : menu déroulant des 9 catégories prédéfinies + option « Autre » révélant un champ libre, sélecteur de date (défaut aujourd'hui, librement modifiable), champ N° de marché (affiché uniquement pour « Marché », suggéré puis éditable), sélecteur de périodicité (`SegmentedButton`), file de synchronisation hors ligne montée (`SyncStatusBar`) — `flutter analyze`/`test`/`build web` ✅.
- **Vérifié en conditions réelles** (2026-09-10, compte de démonstration jetable, établissement réel « Chez Yasmine ») : saisie d'une dépense « Marché » datée la veille via l'application déployée, `expense_date` confirmée en base distincte de `created_at`, allocation pro-rata reflétée dans Graphiques → Bénéfices (voir `docs/api/charts.md`), puis nettoyage complet (dépense, vente/produit de test, compte jetable).
- **Non vérifié en conditions réelles** : un scénario hors-ligne→ligne complet pour une dépense (coupure réseau réelle, retour, synchronisation) — à faire à l'occasion d'une prochaine vérification en conditions réelles.
- **Refonte 4 onglets + Salaires/Paie (2026-09-12)** : 322/322 tests NestJS, `flutter analyze`/`test`/`build web` ✅ (54/54 tests Flutter). Contrainte `expenses_payroll_run_id_key` confirmée en base de production (`pg_constraint`, `contype = 'u'`). Permissions `payroll.manage`/`payroll.view` confirmées en base de production comme accordées uniquement à Administrateur/Comptable/Gérant/Propriétaire/Super Administrateur. Revue de code finale de bout en bout (SHA `fdf2031a0`..`5c51a19c6`, 33 commits) : aucune régression sur `reports.service.ts`/`charts.service.ts` (diff vide), chaîne Employé→Paie→Dépense→Vue d'ensemble/Historique retracée et cohérente, aucun `if` sans accolades dans le code Flutter livré.
- **Non vérifié en conditions réelles** : la checklist manuelle complète en navigateur (double-clic sur « Payer », permissions `payroll.view` seul, responsive desktop) n'a été vérifiée qu'au niveau code/tests automatisés et requêtes SQL directes, pas via une session de navigateur réelle — à faire à l'occasion d'une prochaine vérification en conditions réelles.
- **Correctifs post-revue (2026-09-13)** : rafraîchissement automatique des 4 onglets à la navigation (`ReloadOnTabVisitMixin`), édition/désactivation-réactivation d'un employé, mode de paiement + statut (Payée/En attente) au moment de la saisie manuelle d'une dépense avec action « Annuler » dédiée, KPI de Vue d'ensemble avec évolution en % individuelle (plus seulement le total), libellés français dans l'export Excel de l'Historique, refus serveur d'une dépense manuelle « Salaires » ou d'une modification/suppression d'une dépense liée à un `payrollRunId`. 327/327 tests NestJS, `flutter analyze`/`test`/`build web` ✅ (56/56 tests Flutter). Vérifié au niveau code/tests automatisés uniquement — pas de session de navigateur réelle sur ces correctifs.
