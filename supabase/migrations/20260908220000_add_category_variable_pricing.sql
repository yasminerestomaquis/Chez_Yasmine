-- Catégories à prix variable (ex. Poulets, Poissons, Plats africains) : les
-- produits qui en dépendent n'ont pas de prix d'achat/de vente fixes dans le
-- catalogue — le prix de vente est saisi en caisse à chaque vente, et le prix
-- d'achat correspond à la dépense journalière "Marché" (module Dépenses).
alter table categories
  add column has_variable_pricing boolean not null default false;

-- Le prix de vente d'un produit devient optionnel : nul quand sa catégorie a
-- has_variable_pricing = true (appliqué côté NestJS, jamais côté client).
alter table products
  alter column sale_price drop not null;
