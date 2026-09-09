import { BadRequestException, ConflictException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { AuthorizationService } from '../auth/authorization.service.js';
import type { SupabaseAdminService } from '../auth/supabase-admin.service.js';
import type { PrismaService } from '../prisma/prisma.service.js';
import { UsersService } from './users.service.js';

function makePrismaMock() {
  return {
    userEstablishmentRole: {
      findMany: vi.fn(),
      findFirst: vi.fn(),
      findUniqueOrThrow: vi.fn(),
      delete: vi.fn(),
      update: vi.fn(),
      count: vi.fn(),
    },
    userProfile: { update: vi.fn() },
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
  let supabaseAdmin: { inviteUserByEmail: ReturnType<typeof vi.fn>; generateInviteLink: ReturnType<typeof vi.fn> };
  let service: UsersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    authorization = { getPermissionCodes: vi.fn() };
    supabaseAdmin = { inviteUserByEmail: vi.fn(), generateInviteLink: vi.fn() };
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
      needs_password_setup: true,
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

describe('UsersService.generateInviteLink', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let authorization: { getPermissionCodes: ReturnType<typeof vi.fn> };
  let supabaseAdmin: { inviteUserByEmail: ReturnType<typeof vi.fn>; generateInviteLink: ReturnType<typeof vi.fn> };
  let service: UsersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    authorization = { getPermissionCodes: vi.fn() };
    supabaseAdmin = { inviteUserByEmail: vi.fn(), generateInviteLink: vi.fn() };
    prisma.establishment.findUniqueOrThrow.mockResolvedValue({ id: 'est-1', organizationId: 'org-1' });
    service = new UsersService(
      prisma as unknown as PrismaService,
      authorization as unknown as AuthorizationService,
      supabaseAdmin as unknown as SupabaseAdminService,
    );
  });

  it('never calls the e-mail-sending path — only generateInviteLink', async () => {
    prisma.role.findFirst.mockResolvedValue(roleWithPermissions('Gérant', ['products.manage']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['products.manage']));
    supabaseAdmin.generateInviteLink.mockResolvedValue('https://example.supabase.co/auth/v1/verify?token=abc');

    const result = await service.generateInviteLink('est-1', 'caller-1', { email: 'a@b.com', roleId: 'role-x' });

    expect(supabaseAdmin.generateInviteLink).toHaveBeenCalledWith('a@b.com', {
      invited_establishment_id: 'est-1',
      invited_role_id: 'role-x',
      full_name: '',
      needs_password_setup: true,
    });
    expect(supabaseAdmin.inviteUserByEmail).not.toHaveBeenCalled();
    expect(result).toEqual({
      email: 'a@b.com',
      roleId: 'role-x',
      roleName: 'Gérant',
      link: 'https://example.supabase.co/auth/v1/verify?token=abc',
    });
  });

  it('reuses the same anti-escalation protection as invite()', async () => {
    prisma.role.findFirst.mockResolvedValue(roleWithPermissions('Propriétaire', ['roles.manage']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['products.manage']));

    await expect(
      service.generateInviteLink('est-1', 'caller-1', { email: 'a@b.com', roleId: 'role-x' }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(supabaseAdmin.generateInviteLink).not.toHaveBeenCalled();
  });

  it('surfaces an already-registered email as ConflictException', async () => {
    prisma.role.findFirst.mockResolvedValue(roleWithPermissions('Serveur', ['pos.sell']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['pos.sell']));
    supabaseAdmin.generateInviteLink.mockRejectedValue(new Error('Email already exists'));

    await expect(
      service.generateInviteLink('est-1', 'caller-1', { email: 'a@b.com', roleId: 'role-x' }),
    ).rejects.toBeInstanceOf(ConflictException);
  });
});

const membership = (roleName: string, codes: string[], overrides: Partial<{ userId: string }> = {}) => ({
  id: 'membership-1',
  userId: overrides.userId ?? 'target-user',
  establishmentId: 'est-1',
  roleId: `role-${roleName}`,
  role: roleWithPermissions(roleName, codes),
});

describe('UsersService.removeMember', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let authorization: { getPermissionCodes: ReturnType<typeof vi.fn> };
  let service: UsersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    authorization = { getPermissionCodes: vi.fn() };
    service = new UsersService(
      prisma as unknown as PrismaService,
      authorization as unknown as AuthorizationService,
      {} as unknown as SupabaseAdminService,
    );
  });

  it('throws NotFoundException when the membership does not belong to the establishment', async () => {
    prisma.userEstablishmentRole.findFirst.mockResolvedValue(null);
    await expect(service.removeMember('est-1', 'caller-1', 'membership-x')).rejects.toThrow(NotFoundException);
  });

  it('rejects removing yourself', async () => {
    prisma.userEstablishmentRole.findFirst.mockResolvedValue(membership('Caissier', ['pos.sell'], { userId: 'caller-1' }));
    await expect(service.removeMember('est-1', 'caller-1', 'membership-1')).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.userEstablishmentRole.delete).not.toHaveBeenCalled();
  });

  it('rejects removing a member whose role outranks the caller', async () => {
    prisma.userEstablishmentRole.findFirst.mockResolvedValue(membership('Propriétaire', ['roles.manage']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['products.manage']));
    await expect(service.removeMember('est-1', 'caller-1', 'membership-1')).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.userEstablishmentRole.delete).not.toHaveBeenCalled();
  });

  it('rejects removing the last member who can still manage users', async () => {
    prisma.userEstablishmentRole.findFirst.mockResolvedValue(membership('Gérant', ['users.manage']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['users.manage']));
    prisma.userEstablishmentRole.count.mockResolvedValue(0);
    await expect(service.removeMember('est-1', 'caller-1', 'membership-1')).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.userEstablishmentRole.delete).not.toHaveBeenCalled();
  });

  it('removes a member when allowed', async () => {
    prisma.userEstablishmentRole.findFirst.mockResolvedValue(membership('Serveur', ['pos.sell']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['pos.sell', 'tables.manage']));
    await service.removeMember('est-1', 'caller-1', 'membership-1');
    expect(prisma.userEstablishmentRole.delete).toHaveBeenCalledWith({ where: { id: 'membership-1' } });
  });
});

describe('UsersService.updateMember', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let authorization: { getPermissionCodes: ReturnType<typeof vi.fn> };
  let service: UsersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    authorization = { getPermissionCodes: vi.fn() };
    prisma.establishment.findUniqueOrThrow.mockResolvedValue({ id: 'est-1', organizationId: 'org-1' });
    prisma.userEstablishmentRole.findUniqueOrThrow.mockResolvedValue({ id: 'membership-1', roleId: 'role-Caissier' });
    service = new UsersService(
      prisma as unknown as PrismaService,
      authorization as unknown as AuthorizationService,
      {} as unknown as SupabaseAdminService,
    );
  });

  it('rejects changing your own role', async () => {
    prisma.userEstablishmentRole.findFirst.mockResolvedValue(membership('Caissier', ['pos.sell'], { userId: 'caller-1' }));
    await expect(
      service.updateMember('est-1', 'caller-1', 'membership-1', { roleId: 'role-x' }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('rejects when the caller does not outrank the new role', async () => {
    prisma.userEstablishmentRole.findFirst.mockResolvedValue(membership('Serveur', ['pos.sell']));
    prisma.role.findFirst.mockResolvedValue(roleWithPermissions('Propriétaire', ['roles.manage']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['pos.sell']));
    await expect(
      service.updateMember('est-1', 'caller-1', 'membership-1', { roleId: 'role-x' }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.userEstablishmentRole.update).not.toHaveBeenCalled();
  });

  it('rejects a change that would leave nobody able to manage users', async () => {
    prisma.userEstablishmentRole.findFirst.mockResolvedValue(membership('Gérant', ['users.manage']));
    prisma.role.findFirst.mockResolvedValue(roleWithPermissions('Serveur', ['pos.sell']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['users.manage', 'pos.sell']));
    prisma.userEstablishmentRole.count.mockResolvedValue(0);
    await expect(
      service.updateMember('est-1', 'caller-1', 'membership-1', { roleId: 'role-x' }),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(prisma.userEstablishmentRole.update).not.toHaveBeenCalled();
  });

  it('updates the role when allowed', async () => {
    prisma.userEstablishmentRole.findFirst.mockResolvedValue(membership('Serveur', ['pos.sell', 'tables.manage']));
    prisma.role.findFirst.mockResolvedValue(roleWithPermissions('Caissier', ['pos.sell', 'cash.manage']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['pos.sell', 'tables.manage', 'cash.manage']));

    const result = await service.updateMember('est-1', 'caller-1', 'membership-1', { roleId: 'role-x' });

    expect(prisma.userEstablishmentRole.update).toHaveBeenCalledWith({
      where: { id: 'membership-1' },
      data: { roleId: 'role-x' },
    });
    expect(prisma.userProfile.update).not.toHaveBeenCalled();
    expect(result).toEqual({ id: 'membership-1', roleId: 'role-Caissier' });
  });

  it('allows changing your own full name (no anti-escalation, no self-block)', async () => {
    prisma.userEstablishmentRole.findFirst.mockResolvedValue(membership('Caissier', ['pos.sell'], { userId: 'caller-1' }));

    await service.updateMember('est-1', 'caller-1', 'membership-1', { fullName: 'Nouveau nom' });

    expect(prisma.userProfile.update).toHaveBeenCalledWith({ where: { id: 'caller-1' }, data: { fullName: 'Nouveau nom' } });
    expect(prisma.userEstablishmentRole.update).not.toHaveBeenCalled();
    expect(authorization.getPermissionCodes).not.toHaveBeenCalled();
  });

  it('updates both the role and the full name in one call', async () => {
    prisma.userEstablishmentRole.findFirst.mockResolvedValue(membership('Serveur', ['pos.sell']));
    prisma.role.findFirst.mockResolvedValue(roleWithPermissions('Caissier', ['pos.sell']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['pos.sell']));

    await service.updateMember('est-1', 'caller-1', 'membership-1', { roleId: 'role-x', fullName: 'Missa Key' });

    expect(prisma.userEstablishmentRole.update).toHaveBeenCalledWith({
      where: { id: 'membership-1' },
      data: { roleId: 'role-x' },
    });
    expect(prisma.userProfile.update).toHaveBeenCalledWith({
      where: { id: membership('Serveur', ['pos.sell']).userId },
      data: { fullName: 'Missa Key' },
    });
  });
});

describe('UsersService.generateRecoveryLink', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let authorization: { getPermissionCodes: ReturnType<typeof vi.fn> };
  let supabaseAdmin: { generateRecoveryLink: ReturnType<typeof vi.fn> };
  let service: UsersService;

  beforeEach(() => {
    prisma = makePrismaMock();
    authorization = { getPermissionCodes: vi.fn() };
    supabaseAdmin = { generateRecoveryLink: vi.fn() };
    service = new UsersService(
      prisma as unknown as PrismaService,
      authorization as unknown as AuthorizationService,
      supabaseAdmin as unknown as SupabaseAdminService,
    );
  });

  it('throws NotFoundException when the membership does not belong to the establishment', async () => {
    prisma.userEstablishmentRole.findFirst.mockResolvedValue(null);
    await expect(service.generateRecoveryLink('est-1', 'caller-1', 'membership-x')).rejects.toThrow(NotFoundException);
    expect(supabaseAdmin.generateRecoveryLink).not.toHaveBeenCalled();
  });

  it('rejects generating a link for a member whose role outranks the caller', async () => {
    prisma.userEstablishmentRole.findFirst.mockResolvedValue(membership('Propriétaire', ['roles.manage']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['products.manage']));
    await expect(
      service.generateRecoveryLink('est-1', 'caller-1', 'membership-1'),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(supabaseAdmin.generateRecoveryLink).not.toHaveBeenCalled();
  });

  it('generates a link for the underlying auth user id, not the membership id', async () => {
    prisma.userEstablishmentRole.findFirst.mockResolvedValue(membership('Serveur', ['pos.sell'], { userId: 'target-user' }));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['pos.sell']));
    supabaseAdmin.generateRecoveryLink.mockResolvedValue('https://example.supabase.co/auth/v1/verify?type=recovery&token=abc');

    const result = await service.generateRecoveryLink('est-1', 'caller-1', 'membership-1');

    expect(supabaseAdmin.generateRecoveryLink).toHaveBeenCalledWith('target-user');
    expect(result).toEqual({ link: 'https://example.supabase.co/auth/v1/verify?type=recovery&token=abc' });
  });

  it('translates a Supabase error the same way as invite()', async () => {
    prisma.userEstablishmentRole.findFirst.mockResolvedValue(membership('Serveur', ['pos.sell']));
    authorization.getPermissionCodes.mockResolvedValue(new Set(['pos.sell']));
    supabaseAdmin.generateRecoveryLink.mockRejectedValue(new Error('User not found'));
    await expect(
      service.generateRecoveryLink('est-1', 'caller-1', 'membership-1'),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
