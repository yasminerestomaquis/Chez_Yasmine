-- Élargit la contrainte CHECK de orders.status pour autoriser 'cancelled'
-- (libération d'une table sans condition — OrdersService.release, voir
-- docs/api/tables.md). La contrainte d'origine (20260905191441_core_schema.sql)
-- ne prévoyait que 'open'/'closed', invisible depuis prisma/schema.prisma
-- (champ String simple, sans modélisation des contraintes CHECK) — d'où le
-- 500 en production au premier appel réel de release() avec le statut
-- 'cancelled'.
alter table orders drop constraint orders_status_check;
alter table orders add constraint orders_status_check check (status in ('open', 'closed', 'cancelled'));
