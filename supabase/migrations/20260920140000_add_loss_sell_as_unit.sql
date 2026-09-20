alter table losses add column if not exists sell_as_unit boolean not null default false;

-- Pertes existantes d'un produit vendu par lot ET à l'unité : leur quantité
-- avait été retirée du stock en unités, donc traitées comme « Unité ».
update losses set sell_as_unit = true
where product_id in (select id from products where unit_sale_price is not null);
