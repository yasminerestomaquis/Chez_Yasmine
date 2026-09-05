-- The RLS helper functions are SECURITY DEFINER and only meant to be invoked
-- from within RLS policies for the `authenticated` role. Revoking the default
-- PUBLIC execute grant (Supabase security advisor: anon_security_definer_function_executable).
-- Note: this alone does not remove `anon`'s access — see the next migration.
revoke execute on function current_user_organization_id() from public;
revoke execute on function user_has_establishment_access(uuid) from public;
grant execute on function current_user_organization_id() to authenticated;
grant execute on function user_has_establishment_access(uuid) to authenticated;
