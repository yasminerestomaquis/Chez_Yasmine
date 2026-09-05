-- Supabase grants EXECUTE on new public-schema functions to `anon` and
-- `authenticated` by default (ALTER DEFAULT PRIVILEGES), independently of the
-- PUBLIC pseudo-role — revoking from PUBLIC alone (previous migration) did not
-- remove `anon`'s explicit grant. `anon` never needs these functions: every
-- RLS policy that uses them is scoped `to authenticated` only.
revoke execute on function current_user_organization_id() from anon;
revoke execute on function user_has_establishment_access(uuid) from anon;

-- Residual advisor finding, accepted: `authenticated` can still call these via
-- RPC directly. This is required for RLS policies to evaluate for authenticated
-- queries and is not a data leak — the functions return only the caller's own
-- organization_id or a boolean, never another tenant's data.
