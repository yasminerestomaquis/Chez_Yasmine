-- Chez Yasmine — catalogue de permissions et rôles système par défaut
-- (prompt maître §30). org_id NULL = modèle système, clonable/assignable à
-- toute organisation. Idempotent : peut être rejoué sans dupliquer.

insert into permissions (code, description) values
  ('products.manage',   'Créer/modifier/archiver produits, catégories, photos'),
  ('products.view',     'Consulter le catalogue (produits, catégories, photos) — sans le modifier'),
  ('stock.manage',      'Mouvements de stock : entrées, sorties, inventaires, pertes'),
  ('purchases.manage',  'Achats et fournisseurs'),
  ('pos.sell',          'Encaisser une vente en caisse ou en salle'),
  ('pos.refund',        'Annuler une vente, rembourser'),
  ('tables.manage',     'Plan de salle, ouverture/transfert/fusion/clôture d''addition'),
  ('customers.manage',  'Fiches client'),
  ('credits.manage',    'Ventes à crédit, remboursements de crédit'),
  ('expenses.manage',   'Dépenses'),
  ('losses.manage',     'Pertes de stock'),
  ('cash.manage',       'Ouverture/clôture de caisse'),
  ('reports.view',      'Consultation des rapports et statistiques'),
  ('users.manage',      'Gestion des utilisateurs et de leurs affectations'),
  ('roles.manage',      'Gestion des rôles et permissions'),
  ('settings.manage',   'Paramètres de l''établissement')
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

-- Rôles à accès complet (plateforme / propriétaire) : toutes les permissions.
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
cross join permissions p
where r.is_system and r.name in ('Super Administrateur', 'Administrateur', 'Propriétaire')
on conflict do nothing;

-- Gérant : tout sauf la gestion des rôles.
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
cross join permissions p
where r.is_system and r.name = 'Gérant' and p.code <> 'roles.manage'
on conflict do nothing;

-- Caissier : caisse, remboursement, clients (encours crédit), rapports.
-- `products.view` : la grille produits de la Caisse liste le catalogue
-- (voir apps/api/nestjs/src/catalog/products.controller.ts) — sans elle,
-- un Caissier ne peut même pas ouvrir la Caisse (404/403 au chargement).
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
join permissions p on p.code in ('pos.sell', 'pos.refund', 'customers.manage', 'cash.manage', 'reports.view', 'products.view')
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
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
join permissions p on p.code in ('pos.sell', 'tables.manage', 'products.view', 'reports.view')
where r.is_system and r.name = 'Serveur'
on conflict do nothing;

-- Magasinier : produits, stock, achats/fournisseurs, pertes.
-- `products.view` en plus de `products.manage` : les routes de lecture du
-- catalogue exigent désormais `products.view` spécifiquement (voir
-- ProductsController/CategoriesController/ProductImagesController) —
-- `products.manage` seul ne suffit plus à lister/consulter, seulement à
-- créer/modifier/archiver.
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
join permissions p on p.code in ('products.manage', 'products.view', 'stock.manage', 'purchases.manage', 'losses.manage')
where r.is_system and r.name = 'Magasinier'
on conflict do nothing;

-- Comptable : dépenses, crédits, caisse, rapports.
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
join permissions p on p.code in ('expenses.manage', 'credits.manage', 'cash.manage', 'reports.view')
where r.is_system and r.name = 'Comptable'
on conflict do nothing;
