-- Demande du 2026-10-15 (module Utilisateurs > Gestion des permissions, décompte du stock).
--
-- 1. `sale_items.sell_as_unit` : la ligne a été vendue à l'unité (prix
--    `products.unit_sale_price`) plutôt qu'au lot. Nécessaire au décompte du
--    stock — un lot de 3 retire 3 bouteilles, une unité 1 — pour le
--    remboursement et la correction de quantité, qui doivent restituer/retirer
--    exactement ce que la vente a retiré. Les lignes existantes sont déduites de
--    leur prix (égal au prix à l'unité du produit).
-- 2. Permissions d'affichage de l'Accueil (`home.*`, une par carte) et de saisie
--    des recettes par groupe (`pos.sell_beverages|gbele|plats`).
--    Accordées par défaut de façon à ne rien changer au comportement actuel :
--    tout rôle portant `reports.view` reçoit les `home.*` (le Serveur seulement
--    ce qu'il voyait déjà : recettes boissons sans Gbêlê / Gbêlê et leur détail
--    par mode de paiement), tout rôle portant `pos.sell` reçoit les trois
--    `pos.sell_*`. Rejouable (`on conflict do nothing`).

alter table sale_items add column if not exists sell_as_unit boolean not null default false;

update sale_items si
set sell_as_unit = true
from products p
where p.id = si.product_id
  and p.unit_sale_price is not null
  and si.unit_price = p.unit_sale_price
  and not si.sell_as_unit;

insert into permissions (code, description) values
  ('home.total_sales',            'Accueil : carte « Total ventes »'),
  ('home.cash',                   'Accueil : carte « Espèces »'),
  ('home.mobile_money',           'Accueil : carte « Mobile Money »'),
  ('home.orders',                 'Accueil : carte « Commandes »'),
  ('home.stock_alerts',           'Accueil : carte « Alertes stock »'),
  ('home.revenue_beverages',      'Accueil, RECETTES DU JOUR : Recettes boissons sans Gbêlê'),
  ('home.revenue_gbele',          'Accueil, RECETTES DU JOUR : Recettes Gbêlê'),
  ('home.revenue_plats',          'Accueil, RECETTES DU JOUR : Recettes plats'),
  ('home.detail_beverages_cash',  'Accueil, DÉTAIL PAR MODE DE PAIEMENT : Boissons sans Gbêlê — Espèces'),
  ('home.detail_beverages_mobile','Accueil, DÉTAIL PAR MODE DE PAIEMENT : Boissons sans Gbêlê — Mobile Money'),
  ('home.detail_gbele_cash',      'Accueil, DÉTAIL PAR MODE DE PAIEMENT : Gbêlê — Espèces'),
  ('home.detail_gbele_mobile',    'Accueil, DÉTAIL PAR MODE DE PAIEMENT : Gbêlê — Mobile Money'),
  ('home.detail_plats_cash',      'Accueil, DÉTAIL PAR MODE DE PAIEMENT : Plats — Espèces'),
  ('home.detail_plats_mobile',    'Accueil, DÉTAIL PAR MODE DE PAIEMENT : Plats — Mobile Money'),
  ('pos.sell_beverages',          'Saisir des ventes de boissons sans Gbêlê (Caisse et Tables)'),
  ('pos.sell_gbele',              'Saisir des ventes de Gbêlê (Caisse et Tables)'),
  ('pos.sell_plats',              'Saisir des ventes de plats (Caisse et Tables)')
on conflict (code) do nothing;

insert into role_permissions (role_id, permission_id)
select rp.role_id, c.id
from role_permissions rp
join permissions v on v.id = rp.permission_id and v.code = 'reports.view'
join roles r on r.id = rp.role_id
cross join permissions c
where c.code like 'home.%'
  and (
    r.name <> 'Serveur'
    or c.code in (
      'home.revenue_beverages', 'home.revenue_gbele',
      'home.detail_beverages_cash', 'home.detail_beverages_mobile',
      'home.detail_gbele_cash', 'home.detail_gbele_mobile'
    )
  )
on conflict do nothing;

insert into role_permissions (role_id, permission_id)
select rp.role_id, c.id
from role_permissions rp
join permissions s on s.id = rp.permission_id and s.code = 'pos.sell'
cross join permissions c
where c.code in ('pos.sell_beverages', 'pos.sell_gbele', 'pos.sell_plats')
on conflict do nothing;
