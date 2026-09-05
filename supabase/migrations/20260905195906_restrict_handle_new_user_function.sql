-- handle_new_user() is a trigger function (invoked by Postgres on
-- `auth.users` insert, not by client RPC calls) — it should never be
-- callable directly via /rest/v1/rpc/handle_new_user. Revoking from PUBLIC
-- and explicitly from anon/authenticated (Supabase grants new public-schema
-- functions to them by default, independently of PUBLIC).
revoke execute on function handle_new_user() from public;
revoke execute on function handle_new_user() from anon;
revoke execute on function handle_new_user() from authenticated;
