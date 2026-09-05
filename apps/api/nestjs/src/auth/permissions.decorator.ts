import { SetMetadata } from '@nestjs/common';

export const PERMISSIONS_KEY = 'required_permissions';

/**
 * Marks a route as requiring the given permission codes (see
 * supabase/seed/001_roles_permissions.sql for the catalog) on the
 * establishment identified by the `:establishmentId` route param.
 * Must be combined with SupabaseJwtGuard (runs first) and PermissionsGuard.
 */
export const RequirePermissions = (...permissions: string[]) => SetMetadata(PERMISSIONS_KEY, permissions);
