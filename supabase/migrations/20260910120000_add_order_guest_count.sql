-- Nombre de convives saisi à l'ouverture d'une table, pour l'affichage
-- "X pers." sur les cartes de l'écran Tables (Nouvel interface _ 1.docx).
-- Facultatif : aucune valeur par défaut imposée, une commande existante
-- sans convive renseigné reste valide (nullable).
alter table orders add column if not exists guest_count integer;
