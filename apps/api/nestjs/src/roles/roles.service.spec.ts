import { ConflictException, NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { RolesService } from './roles.service.js';

function makePrismaMock() {
  return {
    establishment: { findUniqueOrThrow: vi.fn() },
    permission: { findMany: vi.fn(), findUnique: vi.fn() },
    role: { findMany: vi.fn(), findFirst: vi.fn() },
    rolePermission: { createMany: vi.fn(), deleteMany: vi.fn() },
    userEstablishmentRole: { count: vi.fn() },
  };
}

describe('RolesService', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: RolesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new RolesService(prisma as unknown as PrismaService);
  });

  describe('listMatrix', () => {
    it('returns every permission and every role with its granted permission codes', async () => {
      prisma.establishment.findUniqueOrThrow.mockResolvedValue({ id: 'est-1', organizationId: 'org-1' });
      prisma.permission.findMany.mockResolvedValue([
        { code: 'pos.sell', description: 'Encaisser' },
        { code: 'pos.refund', description: 'Rembourser' },
      ]);
      prisma.role.findMany.mockResolvedValue([
        {
          id: 'role-caissier',
          name: 'Caissier',
          isSystem: true,
          rolePermissions: [{ permission: { code: 'pos.sell' } }],
        },
        {
          id: 'role-superadmin',
          name: 'Super Administrateur',
          isSystem: true,
          rolePermissions: [{ permission: { code: 'pos.sell' } }, { permission: { code: 'pos.refund' } }],
        },
      ]);

      const result = await service.listMatrix('est-1');

      expect(prisma.role.findMany).toHaveBeenCalledWith(
        expect.objectContaining({ where: { OR: [{ isSystem: true }, { organizationId: 'org-1' }] } }),
      );
      expect(result).toEqual({
        permissions: [
          { code: 'pos.sell', description: 'Encaisser' },
          { code: 'pos.refund', description: 'Rembourser' },
        ],
        roles: [
          { id: 'role-caissier', name: 'Caissier', isSystem: true, permissionCodes: ['pos.sell'] },
          { id: 'role-superadmin', name: 'Super Administrateur', isSystem: true, permissionCodes: ['pos.sell', 'pos.refund'] },
        ],
      });
    });
  });

  describe('grant', () => {
    it('creates the role_permission row idempotently (skipDuplicates)', async () => {
      prisma.establishment.findUniqueOrThrow.mockResolvedValue({ id: 'est-1', organizationId: 'org-1' });
      prisma.role.findFirst.mockResolvedValue({ id: 'role-1', name: 'Serveur' });
      prisma.permission.findUnique.mockResolvedValue({ id: 'perm-1', code: 'pos.refund' });

      await service.grant('est-1', 'role-1', 'pos.refund');

      expect(prisma.rolePermission.createMany).toHaveBeenCalledWith({
        data: [{ roleId: 'role-1', permissionId: 'perm-1' }],
        skipDuplicates: true,
      });
    });

    it('throws NotFoundException when the role does not exist for this establishment', async () => {
      prisma.establishment.findUniqueOrThrow.mockResolvedValue({ id: 'est-1', organizationId: 'org-1' });
      prisma.role.findFirst.mockResolvedValue(null);
      prisma.permission.findUnique.mockResolvedValue({ id: 'perm-1', code: 'pos.refund' });

      await expect(service.grant('est-1', 'role-x', 'pos.refund')).rejects.toBeInstanceOf(NotFoundException);
      expect(prisma.rolePermission.createMany).not.toHaveBeenCalled();
    });

    it('throws NotFoundException for an unknown permission code', async () => {
      prisma.establishment.findUniqueOrThrow.mockResolvedValue({ id: 'est-1', organizationId: 'org-1' });
      prisma.role.findFirst.mockResolvedValue({ id: 'role-1', name: 'Serveur' });
      prisma.permission.findUnique.mockResolvedValue(null);

      await expect(service.grant('est-1', 'role-1', 'not.a.real.code')).rejects.toBeInstanceOf(NotFoundException);
      expect(prisma.rolePermission.createMany).not.toHaveBeenCalled();
    });
  });

  describe('revoke', () => {
    beforeEach(() => {
      prisma.establishment.findUniqueOrThrow.mockResolvedValue({ id: 'est-1', organizationId: 'org-1' });
    });

    it('always refuses to remove roles.manage from Super Administrateur, without even checking other holders', async () => {
      prisma.role.findFirst.mockResolvedValue({ id: 'role-superadmin', name: 'Super Administrateur' });
      prisma.permission.findUnique.mockResolvedValue({ id: 'perm-roles', code: 'roles.manage' });

      await expect(service.revoke('est-1', 'role-superadmin', 'roles.manage')).rejects.toBeInstanceOf(ConflictException);
      expect(prisma.userEstablishmentRole.count).not.toHaveBeenCalled();
      expect(prisma.rolePermission.deleteMany).not.toHaveBeenCalled();
    });

    it('refuses to remove users.manage from a role if no one else would still hold it', async () => {
      prisma.role.findFirst.mockResolvedValue({ id: 'role-admin', name: 'Administrateur' });
      prisma.permission.findUnique.mockResolvedValue({ id: 'perm-users', code: 'users.manage' });
      prisma.userEstablishmentRole.count.mockResolvedValue(0);

      await expect(service.revoke('est-1', 'role-admin', 'users.manage')).rejects.toBeInstanceOf(ConflictException);
      expect(prisma.rolePermission.deleteMany).not.toHaveBeenCalled();
    });

    it('allows removing users.manage when at least one other assigned membership would still hold it', async () => {
      prisma.role.findFirst.mockResolvedValue({ id: 'role-admin', name: 'Administrateur' });
      prisma.permission.findUnique.mockResolvedValue({ id: 'perm-users', code: 'users.manage' });
      prisma.userEstablishmentRole.count.mockResolvedValue(1);

      await service.revoke('est-1', 'role-admin', 'users.manage');

      expect(prisma.userEstablishmentRole.count).toHaveBeenCalledWith({
        where: { roleId: { not: 'role-admin' }, role: { rolePermissions: { some: { permission: { code: 'users.manage' } } } } },
      });
      expect(prisma.rolePermission.deleteMany).toHaveBeenCalledWith({
        where: { roleId: 'role-admin', permissionId: 'perm-users' },
      });
    });

    it('removes an ordinary permission directly, without any last-holder check', async () => {
      prisma.role.findFirst.mockResolvedValue({ id: 'role-serveur', name: 'Serveur' });
      prisma.permission.findUnique.mockResolvedValue({ id: 'perm-refund', code: 'pos.refund' });

      await service.revoke('est-1', 'role-serveur', 'pos.refund');

      expect(prisma.userEstablishmentRole.count).not.toHaveBeenCalled();
      expect(prisma.rolePermission.deleteMany).toHaveBeenCalledWith({
        where: { roleId: 'role-serveur', permissionId: 'perm-refund' },
      });
    });

    it('throws NotFoundException when the role does not exist for this establishment', async () => {
      prisma.role.findFirst.mockResolvedValue(null);
      prisma.permission.findUnique.mockResolvedValue({ id: 'perm-refund', code: 'pos.refund' });

      await expect(service.revoke('est-1', 'role-x', 'pos.refund')).rejects.toBeInstanceOf(NotFoundException);
      expect(prisma.rolePermission.deleteMany).not.toHaveBeenCalled();
    });
  });
});
