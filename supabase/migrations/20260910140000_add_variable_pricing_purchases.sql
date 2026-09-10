-- Permet une ligne de commande pour un produit à prix variable (Poulets,
-- Poissons, Plats africains) : quantité achetée + prix d'achat unitaire
-- connus directement (pas de casier), à la différence des catégories à prix
-- par casier qui utilisent cases_ordered/bottles_per_case/purchase_price_per_case.
-- Ces trois colonnes deviennent nullables : elles ne s'appliquent qu'aux
-- lignes "par casier" ; une ligne "prix variable" les laisse à NULL et
-- s'appuie uniquement sur quantity/unit_price (déjà génériques).
alter table purchase_items alter column cases_ordered drop not null;
alter table purchase_items alter column bottles_per_case drop not null;
alter table purchase_items alter column purchase_price_per_case drop not null;
