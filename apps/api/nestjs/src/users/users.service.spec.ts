import { BadRequestException, ConflictException, ForbiddenException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { AuthorizationService } from '../auth/authorization.service.js';
import type { SupabaseAdminService } from '../auth/supabase-admin.service.js';
import type { PrismaService } from '../prisma/prisma.service.js';
import { UsersService } from './users.service.js';

function makePrismaMock() {
  return {
    userEstablishmentRole: { findMany: vi.fn() },
    establishment: { findUniqueOrThrow: vi.fn() },
    role: { findMany: vi.fn(), findFirst: vi.fn() },
  };
}

const roleWithPermissions = (name: string, codes: string[], overrides: Partial<{ isSystem: boolean; organizationId: string | null }> = {}) => ({
  id: `role-${name}`,
  name,
  isSystem: overrides.isSystem ?? true,
  organizationId: overrides.organizationId ?? null,
  rolePermissions: codes.map((code) => ({ permission: { code } })),
});

describe('UsersService.invite', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let authorization: { getPermissionCodes: ReturnType<typeof vi.fn> };
  let supabaseAdmin: { inviteUserByEmail: ReturnType<typeof vi.fn> };
  let service: UsersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    authorization = { getPermissionCodes: vi.fn() };
    supabaseAdmin = { inviteUserByEmail: vi.fn() };
    prisma.establishment.findUniqueOrThrow.mockResolvedValue({ id: 'est-1', organizationId: 'org-1' });
    service = new UsersService(
      prisma as unknown as PrismaService,
      authorization as unknown as AuthorizationService,
      supabaseAdmin as unknown as SupabaseAdminService,
    );
  });

  it('rejects an unknown role', async () => {
    prisma.role.findFirst.mockResolvedValue(null);
    await expect(
      service.invite('est-1', 'caller-1', { email: 'a@b.com', roleId: 'role-x' }),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(supabaseAdmin.inviteUserByEmail).not.toHaveBeenCalled();
  });

  it("rejects a role belonging to another organization", async () => {
    prisma.role.findFirst.mockResolvedValue(
      roleWithPermissions('Gérant local', ['pos.sell'], { isSystem: false, organizationId: 'org-2' }),
    );
    await expect(
      service.invite('est-1', 'caller-1', { email: 'a@b.com', roleId: 'role-x' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('blocks assigning a role that grants a permission the caller does not have (anti-escalation)', async () => {
    prisma.role.findFirst.mockResolvedValue(roleWithPermissions('Propriétaire', ['products.manage', 'roles.manage']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['products.manage'])); // pas roles.manage

    await expect(
      service.invite('est-1', 'caller-1', { email: 'a@b.com', roleId: 'role-x' }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(supabaseAdmin.inviteUserByEmail).not.toHaveBeenCalled();
  });

  it('allows assigning a role whose permissions are a subset of the caller’s own', async () => {
    prisma.role.findFirst.mockResolvedValue(roleWithPermissions('Caissier', ['pos.sell', 'cash.manage']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['pos.sell', 'cash.manage', 'users.manage']));

    const result = await service.invite('est-1', 'caller-1', { email: 'a@b.com', roleId: 'role-x' });

    expect(supabaseAdmin.inviteUserByEmail).toHaveBeenCalledWith('a@b.com', {
      invited_establishment_id: 'est-1',
      invited_role_id: 'role-x',
      full_name: '',
    });
    expect(result).toEqual({ email: 'a@b.com', roleId: 'role-x', roleName: 'Caissier' });
  });

  it('surfaces an already-registered email as ConflictException', async () => {
    prisma.role.findFirst.mockResolvedValue(roleWithPermissions('Serveur', ['pos.sell']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['pos.sell']));
    supabaseAdmin.inviteUserByEmail.mockRejectedValue(new Error('A user with this email address has already been registered'));

    await expect(
      service.invite('est-1', 'caller-1', { email: 'a@b.com', roleId: 'role-x' }),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('wraps any other Supabase error as BadRequestException', async () => {
    prisma.role.findFirst.mockResolvedValue(roleWithPermissions('Serveur', ['pos.sell']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['pos.sell']));
    supabaseAdmin.inviteUserByEmail.mockRejectedValue(new Error('SMTP quota exceeded'));

    await expect(
      service.invite('est-1', 'caller-1', { email: 'a@b.com', roleId: 'role-x' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
