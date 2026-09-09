-- Chez Yasmine — invitation d'un utilisateur dans un établissement existant
-- (module Utilisateurs, apps/api/nestjs/src/users/) : `handle_new_user`
-- (20260905193641_auth_bootstrap_trigger.sql) crée inconditionnellement une
-- nouvelle organisation/établissement/rôle Propriétaire à chaque insertion
-- dans auth.users — correct pour l'auto-inscription (signUp), mais faux pour
-- une invitation admin (supabase.auth.admin.inviteUserByEmail), qui insère
-- aussi une ligne dans auth.users : sans ce correctif, la personne invitée
-- se retrouverait avec un établissement fantôme en plus de celui auquel on
-- voulait l'affecter.
--
-- NestJS (UsersService.invite, clé service_role) passe désormais
-- invited_establishment_id/invited_role_id dans les métadonnées de
-- l'invitation ; ce trigger les détecte et rattache directement l'utilisateur
-- à l'établissement/rôle choisis, sans créer de nouvelle organisation.
-- Comportement de l'auto-inscription normale inchangé.

create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_establishment_id uuid;
  v_role_id uuid;
  v_org_name text;
begin
  if new.raw_user_meta_data ? 'invited_establishment_id' then
    v_establishment_id := (new.raw_user_meta_data->>'invited_establishment_id')::uuid;
    v_role_id := (new.raw_user_meta_data->>'invited_role_id')::uuid;

    select organization_id into v_org_id from establishments where id = v_establishment_id;
    if v_org_id is null then
      raise exception 'invited_establishment_id % introuvable', v_establishment_id;
    end if;

    insert into user_profiles (id, organization_id, full_name)
      values (new.id, v_org_id, new.raw_user_meta_data->>'full_name');
    insert into user_establishment_roles (user_id, establishment_id, role_id)
      values (new.id, v_establishment_id, v_role_id);

    return new;
  end if;

  v_org_name := coalesce(nullif(trim(new.raw_user_meta_data->>'organization_name'), ''), 'Mon établissement');

  insert into organizations (name) values (v_org_name) returning id into v_org_id;
  insert into establishments (organization_id, name) values (v_org_id, v_org_name) returning id into v_establishment_id;
  insert into user_profiles (id, organization_id, full_name)
    values (new.id, v_org_id, new.raw_user_meta_data->>'full_name');

  select id into v_role_id from roles where is_system and name = 'Propriétaire';
  if v_role_id is not null then
    insert into user_establishment_roles (user_id, establishment_id, role_id)
      values (new.id, v_establishment_id, v_role_id);
  end if;

  return new;
end;
$$;
