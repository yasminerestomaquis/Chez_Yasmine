-- Chez Yasmine — catalogue de permissions et rôles système par défaut
-- (prompt maître §30). org_id NULL = modèle système, clonable/assignable à
-- toute organisation. Idempotent : peut être rejoué sans dupliquer.

insert into permissions (code, description) values
  ('products.manage',   'Créer/modifier/archiver produits, catégories, photos'),
  ('products.view',     'Consulter le catalogue (produits, catégories, photos) — sans le modifier'),
  ('stock.manage',      'Mouvements de stock : entrées, sorties, inventaires, pertes'),
  ('stock.view',        'Consulter le stock, son historique et ses alertes — sans créer de mouvement'),
  ('purchases.manage',  'Achats et fournisseurs'),
  ('purchases.view',    'Consulter l''historique des commandes d''achat — sans les créer/modifier/recevoir/annuler'),
  ('pos.sell',          'Encaisser une vente en caisse ou en salle'),
  ('pos.refund',        'Annuler une vente, rembourser'),
  ('pos.correct',       'Corriger une vente déjà enregistrée (quantité, mode de paiement) sans la rembourser entièrement'),
  ('tables.manage',     'Plan de salle, ouverture/transfert/fusion/clôture d''addition'),
  ('customers.manage',  'Fiches client'),
  ('credits.manage',    'Ventes à crédit, remboursements de crédit'),
  ('expenses.manage',   'Dépenses'),
  ('losses.manage',     'Pertes de stock'),
  ('cash.manage',       'Ouverture/clôture de caisse'),
  ('reports.view',      'Consultation des rapports et statistiques'),
  ('users.manage',      'Gestion des utilisateurs et de leurs affectations'),
  ('roles.manage',      'Gestion des rôles et permissions'),
  ('settings.manage',   'Paramètres de l''établissement'),
  ('payroll.manage',    'Gérer les employés et le workflow de paie (préparer/valider/payer/annuler)'),
  ('payroll.view',      'Consulter les employés, la paie et son historique — sans les modifier'),
  ('notifications.manage', 'Effacer toutes les notifications de l''organisation — réservé au Super Administrateur')
on conflict (code) do nothing;

insert into roles (organization_id, name, is_system) values
  (null, 'Super Administrateur', true),
  (null, 'Administrateur',       true),
  (null, 'Propriétaire',         true),
  (null, 'Gérant',               true),
  (null, 'Caissier',             true),
  (null, 'Serveur',              true),
  (null, 'Magasinier',           true),
  (null, 'Comptable',            true)
on conflict (name) where organization_id is null do nothing;

-- Rôles à accès complet (plateforme / propriétaire) : toutes les permissions
-- sauf notifications.manage (décision utilisateur du 2026-09-13 : réservée
-- au seul Super Administrateur, jamais à Administrateur/Propriétaire malgré
-- leur accès par ailleurs complet — voir la grille dédiée plus bas).
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
cross join permissions p
where r.is_system and r.name in ('Super Administrateur', 'Administrateur', 'Propriétaire')
  and p.code <> 'notifications.manage'
on conflict do nothing;

-- notifications.manage : Super Administrateur uniquement (bouton "Effacer
-- toutes les notifications", voir docs/api/notifications.md).
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
join permissions p on p.code = 'notifications.manage'
where r.is_system and r.name = 'Super Administrateur'
on conflict do nothing;

-- Gérant : tout sauf la gestion des rôles, des utilisateurs et du catalogue
-- (décision utilisateur du 2026-09-13 pour les deux premiers — le module
-- Utilisateurs reste réservé à Super Administrateur/Administrateur/
-- Propriétaire ; décision utilisateur du 2026-09-15 pour le catalogue —
-- `products.view` volontairement PAS exclue : le Gérant garde le droit de
-- consulter le catalogue, notamment parce qu'Achats en dépend pour choisir
-- un produit à commander (voir purchase_order_detail_page.dart) — seule la
-- création/modification/suppression de produits/catégories/photos lui est
-- retirée, voir docs/api/catalog.md).
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
cross join permissions p
where r.is_system and r.name = 'Gérant' and p.code not in ('roles.manage', 'users.manage', 'products.manage')
on conflict do nothing;

-- Caissier : caisse, remboursement, clients (encours crédit), rapports.
-- `products.view` : la grille produits de la Caisse liste le catalogue
-- (voir apps/api/nestjs/src/catalog/products.controller.ts) — sans elle,
-- un Caissier ne peut même pas ouvrir la Caisse (404/403 au chargement).
-- `pos.correct` (2026-09-16) : ajoutée explicitement en plus de `pos.refund`
-- — depuis la séparation des deux permissions, plus rien ne l'accorderait
-- automatiquement au Caissier, qui devait déjà pouvoir corriger une vente
-- (la possédait via `pos.refund` avant la séparation).
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
join permissions p on p.code in ('pos.sell', 'pos.refund', 'pos.correct', 'customers.manage', 'cash.manage', 'reports.view', 'products.view')
where r.is_system and r.name = 'Caissier'
on conflict do nothing;

-- Serveur : vente en salle et gestion des tables.
-- `products.view` : même raison que pour Caissier ci-dessus — la prise de
-- commande en salle (FloorPlanPage/TableOrderPage) liste aussi le catalogue.
-- `reports.view` (2026-09-11, demande utilisateur) : uniquement pour que
-- l'accueil affiche les 3 cartes "Recettes boissons" (jour/Espèces/Mobile
-- Money) — HomeDashboard masque volontairement pour ce rôle le reste des
-- indicateurs (ventes plats, total, commandes, alertes stock), voir
-- lib/home/home_dashboard.dart.
-- `purchases.view`/`stock.view` (2026-09-11, demande utilisateur) : accès en
-- lecture seule à l'onglet Historique d'Achats et à tout le module Stock
-- (sans "Valeur du stock", masquée côté client — voir lib/stock/stock_page.dart)
-- — jamais `purchases.manage`/`stock.manage`, qui resteraient réservés à
-- Magasinier/Gérant/administration.
-- `losses.manage` (2026-09-15, demande utilisateur) : accès complet au
-- module Pertes — contrairement à products/stock/purchases, il n'existe pas
-- de `losses.view` séparée (voir `LossesController`, une seule permission
-- gate à la fois la consultation et l'enregistrement d'une perte).
-- `pos.correct` (2026-09-16, demande utilisateur) : le Serveur peut corriger
-- la quantité vendue et le mode de paiement d'une ligne déjà enregistrée
-- (boutons de `CategorySoldItemsPage`, Caisse et Addition) — délibérément
-- SANS `pos.refund` : il ne peut toujours pas annuler une vente entière,
-- seule la correction lui est accordée (voir `SalesController`).
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
join permissions p on p.code in ('pos.sell', 'tables.manage', 'products.view', 'reports.view', 'purchases.view', 'stock.view', 'losses.manage', 'pos.correct')
where r.is_system and r.name = 'Serveur'
on conflict do nothing;

-- Magasinier : produits, stock, achats/fournisseurs, pertes.
-- `products.view`/`stock.view`/`purchases.view` en plus de leurs pendants
-- `.manage` : les routes de lecture (catalogue, historique stock/achats,
-- alertes) exigent désormais le permis de lecture spécifiquement (voir
-- ProductsController/CategoriesController/ProductImagesController/
-- StockController/PurchasesController) — `.manage` seul ne suffit plus à
-- lister/consulter, seulement à créer/modifier/archiver.
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
join permissions p on p.code in ('products.manage', 'products.view', 'stock.manage', 'stock.view', 'purchases.manage', 'purchases.view', 'losses.manage')
where r.is_system and r.name = 'Magasinier'
on conflict do nothing;

-- Comptable : dépenses, crédits, caisse, rapports.
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
join permissions p on p.code in ('expenses.manage', 'credits.manage', 'cash.manage', 'reports.view')
where r.is_system and r.name = 'Comptable'
on conflict do nothing;

-- Comptable : rôle le plus pertinent pour la Paie (voir docs/api/expenses.md).
-- `payroll.manage` inclut `payroll.view` par convention (comme
-- products/stock/purchases) : accordé explicitement pour ne pas dépendre
-- d'un futur découplage.
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
join permissions p on p.code in ('payroll.manage', 'payroll.view')
where r.is_system and r.name = 'Comptable'
on conflict do nothing;
