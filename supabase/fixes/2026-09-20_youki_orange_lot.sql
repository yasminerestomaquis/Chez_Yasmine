-- Correction de données (demande utilisateur du 2026-09-20) — Youki Orange.
-- Objectif : Quantité reçue 24, Consommé 9, Perdu 2, Restant 13 (stock actuel 13 inchangé).
-- À exécuter une seule fois (SQL editor Supabase). Non versionné comme migration : c'est une correction de données.
--
-- 1. Supprime l'entrée initiale de 12, sa sortie de correction (12) et l'ajustement +10.
-- 2. Porte l'entrée « Correction commande n°1 » à 24.
-- 3. Enregistre la perte de 2 (ligne Pertes + mouvement de stock), rattachée à la commande n°1.
-- Stock : 24 - 9 (ventes) - 2 (perte) = 13.
--
-- ⚠ La commande n°1 (Achats) porte toujours 12 bouteilles pour Youki Orange ; corrigez-la
-- dans le module Achats si elle doit aussi afficher 24.

begin;

with adj as (
  select created_by, created_at from stock_movements where id = 'bb758b21-31c4-4c43-a225-b5d8a3459361'
),
del as (
  delete from stock_movements
  where id in (
    'e7c9532b-1095-4ce1-b8e1-a6ed7f7fb4bf',
    '80e0d563-f82d-4c0b-8896-7982011fdb20',
    'bb758b21-31c4-4c43-a225-b5d8a3459361'
  )
  returning id
),
upd as (
  update stock_movements set quantity = 24 where id = '155161ff-4fec-4c87-afff-15cafb9a45a6' returning id
),
mv as (
  insert into stock_movements (product_id, type, quantity, reason, created_by, created_at)
  select '3264d210-e5b5-44f8-8195-6d0d0b97cf36', 'loss', 2, 'Commande n°1 — Correction du point du 20/09/2026', created_by, created_at from adj
  returning id
)
insert into losses (establishment_id, product_id, quantity, reason, order_number, created_by, created_at)
select '55f0acc0-d3d3-4030-af86-6f4016cdba11', '3264d210-e5b5-44f8-8195-6d0d0b97cf36', 2, 'Correction du point du 20/09/2026', 1, created_by, created_at from adj;

-- Vérification : doit renvoyer stock_quantity = 13.
select name, stock_quantity from products where id = '3264d210-e5b5-44f8-8195-6d0d0b97cf36';

commit;
