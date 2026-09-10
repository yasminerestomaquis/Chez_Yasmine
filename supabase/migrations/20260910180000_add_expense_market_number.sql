-- Numéro de marché (N° de marché), suggestion éditable pour les dépenses de
-- nature "Marché" — même principe que Purchase.order_number : jamais imposé
-- ni contraint en unicité côté serveur.
alter table expenses add column market_number integer;
