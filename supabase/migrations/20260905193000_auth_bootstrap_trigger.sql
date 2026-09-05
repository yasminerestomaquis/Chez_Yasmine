-- Chez Yasmine — bootstrap applicatif à l'inscription Supabase Auth
--
-- Un utilisateur qui s'inscrit directement (propriétaire créant son compte)
-- n'a par définition pas encore d'organisation : `user_profiles.organization_id`
-- est NOT NULL, donc on ne peut pas laisser le client (RLS l'en empêcherait de
-- toute façon) créer lui-même son organisation avant d'exister en tant
-- qu'utilisateur. Ce trigger, exécuté en SECURITY DEFINER (contourne RLS),
-- crée automatiquement à l'inscription : une organisation, un établissement,
-- le profil utilisateur, et l'affectation du rôle système « Propriétaire ».
--
-- Le nom de l'organisation/établissement est lu dans les métadonnées passées
-- par le client à l'inscription (`options.data` de `supabase.auth.signUp`) :
--   { "organization_name": "Chez Yasmine", "full_name": "Yasmine ..." }
--
-- Portée volontairement limitée à l'auto-inscription du propriétaire (cas
-- d'usage MVP mono-établissement). L'invitation d'utilisateurs supplémentaires
-- dans une organisation existante est un flux distinct, à traiter par NestJS
-- (service_role) plutôt que par ce trigger — non traité dans cette migration.

create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_establishment_id uuid;
  v_owner_role_id uuid;
  v_org_name text;
begin
  v_org_name := coalesce(nullif(trim(new.raw_user_meta_data->>'organization_name'), ''), 'Mon établissement');

  insert into organizations (name) values (v_org_name) returning id into v_org_id;
  insert into establishments (organization_id, name) values (v_org_id, v_org_name) returning id into v_establishment_id;
  insert into user_profiles (id, organization_id, full_name)
    values (new.id, v_org_id, new.raw_user_meta_data->>'full_name');

  select id into v_owner_role_id from roles where is_system and name = 'Propriétaire';
  if v_owner_role_id is not null then
    insert into user_establishment_roles (user_id, establishment_id, role_id)
      values (new.id, v_establishment_id, v_owner_role_id);
  end if;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();
