-- Lets the system-role seed (supabase/seed/001_roles_permissions.sql) be
-- idempotent via ON CONFLICT: two system role templates (organization_id is
-- null) must not share a name. Org-scoped roles are unrestricted here.
create unique index roles_system_name_unique on roles(name) where organization_id is null;
