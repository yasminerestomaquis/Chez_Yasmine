-- Achat par casier (Bières, Vins, Sucreries) : nouveaux champs Catalogue
-- (Category.has_case_pricing, Product.bottles_per_case/purchase_price_per_case)
-- et nouveau flux de commande (Purchase.order_number/order_date,
-- PurchaseItem.cases_ordered/bottles_per_case/purchase_price_per_case).

alter table categories
  add column has_case_pricing boolean not null default false;

alter table products
  add column bottles_per_case int,
  add column purchase_price_per_case numeric(12, 2);

alter table purchases
  add column order_number int,
  add column order_date date not null default current_date;

-- order_number rétroactif pour les achats déjà existants (pas de sous-module
-- "N° de commande" avant cette migration) : numérotation par fournisseur
-- selon l'ordre de création, en repartant de 1.
with numbered as (
  select id, row_number() over (
    partition by establishment_id, supplier_id order by created_at asc
  ) as rn
  from purchases
)
update purchases p
set order_number = numbered.rn
from numbered
where p.id = numbered.id;

alter table purchases
  alter column order_number set not null;

alter table purchase_items
  add column cases_ordered numeric(12, 2),
  add column bottles_per_case int,
  add column purchase_price_per_case numeric(12, 2);

-- Repli pour les lignes d'achat déjà existantes (créées avant ce flux par
-- casier) : un "casier" fictif d'une seule bouteille, pour que les nouvelles
-- colonnes ne soient jamais nulles sans fausser quantity/unitPrice déjà en place.
update purchase_items
set cases_ordered = quantity,
    bottles_per_case = 1,
    purchase_price_per_case = unit_price
where cases_ordered is null;

alter table purchase_items
  alter column cases_ordered set not null,
  alter column bottles_per_case set not null,
  alter column purchase_price_per_case set not null;
