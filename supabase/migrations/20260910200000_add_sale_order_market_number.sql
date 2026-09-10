-- Rattache une vente (ses lignes Bières/Vins/Sucreries et/ou Poulets/Poissons/
-- Plats africains) au N° de commande d'achat / N° de marché en cours — saisi
-- en caisse, jamais imposé ni vérifié contre une commande/dépense existante.
alter table sales add column order_number integer;
alter table sales add column market_number integer;
