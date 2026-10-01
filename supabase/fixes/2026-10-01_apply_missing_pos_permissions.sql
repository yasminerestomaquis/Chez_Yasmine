-- Rattrapage production (2026-10-01) — `pos.correct_price` et `pos.set_date`.
-- supabase/seed/001_roles_permissions.sql n'est PAS rejoué automatiquement au
-- déploiement (seules les migrations le sont) : ces deux permissions, ajoutées
-- au seed dans les commits cf00a60 (pos.correct_price) et 117f65b/29b713a
-- (pos.set_date), n'existaient donc pas encore dans le catalogue `permissions`
-- en production. Conséquence concrète avant ce correctif :
--   - `pos.correct_price` (correction du prix de vente, réservée au Super
--     Administrateur) était inutilisable par QUICONQUE, y compris le Super
--     Administrateur, puisqu'aucun rôle ne pouvait porter une permission
--     inexistante.
--   - `pos.set_date` (date choisie à l'encaissement) était dans le même cas :
--     le serveur refusait systématiquement `dto.createdAt` (403), quel que
--     soit le rôle — le bouton Date restait visible côté client (gating
--     indépendant de la base), mais la validation échouait pour tout le monde.
--   - Les deux permissions étaient de toute façon absentes de « Gestion des
--     permissions », qui liste le catalogue `permissions` : impossible de les
--     accorder/révoquer depuis le tableau de bord.
--
-- Déjà exécuté une fois (SQL editor Supabase, projet tsebsulvhgttdwtgqfoj) le
-- 2026-10-01. Non versionné comme migration : correction de données de
-- rattrapage, idempotente (on conflict do nothing), reproductible si besoin
-- sur un autre environnement.

begin;

insert into permissions (code, description) values
  ('pos.correct_price', 'Modifier le prix de vente d''une ligne de vente déjà enregistrée — réservé au Super Administrateur'),
  ('pos.set_date',      'Choisir la date d''une vente au moment de l''encaissement (Caisse/Tables), plutôt que la date du jour')
on conflict (code) do nothing;

-- pos.set_date : Super Administrateur / Administrateur / Propriétaire / Gérant
-- (règle "tout sauf" du seed actuel — non exclue), + Caissier explicitement.
-- PAS le Serveur (demande utilisateur explicite du 2026-10-01).
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
join permissions p on p.code = 'pos.set_date'
where r.is_system and r.name in ('Super Administrateur', 'Administrateur', 'Propriétaire', 'Gérant', 'Caissier')
on conflict do nothing;

-- pos.correct_price : Super Administrateur uniquement.
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
join permissions p on p.code = 'pos.correct_price'
where r.is_system and r.name = 'Super Administrateur'
on conflict do nothing;

-- Vérification : doit renvoyer exactement —
--   pos.correct_price : Super Administrateur
--   pos.set_date       : Administrateur, Caissier, Gérant, Propriétaire, Super Administrateur
select r.name, p.code
from roles r
join role_permissions rp on rp.role_id = r.id
join permissions p on p.id = rp.permission_id
where p.code in ('pos.set_date', 'pos.correct_price')
order by p.code, r.name;

commit;
