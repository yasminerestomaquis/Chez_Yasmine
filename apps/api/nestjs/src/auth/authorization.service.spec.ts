import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { AuthorizationService } from './authorization.service.js';

function makePrismaMock() {
  return { userEstablishmentRole: { findMany: vi.fn() } };
}

describe('AuthorizationService.getPermissionCodes', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: AuthorizationService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new AuthorizationService(prisma as unknown as PrismaService);
  });

  it('returns an empty set for a user with no role on the establishment', async () => {
    prisma.userEstablishmentRole.findMany.mockResolvedValue([]);
    const codes = await service.getPermissionCodes('user-1', 'est-1');
    expect(codes.size).toBe(0);
  });

  it('unions permission codes across every role the user holds on the establishment', async () => {
    prisma.userEstablishmentRole.findMany.mockResolvedValue([
      { role: { rolePermissions: [{ permission: { code: 'stock.manage' } }, { permission: { code: 'pos.sell' } }] } },
      { role: { rolePermissions: [{ permission: { code: 'pos.sell' } }, { permission: { code: 'reports.view' } }] } },
    ]);

    const codes = await service.getPermissionCodes('user-1', 'est-1');

    expect([...codes].sort()).toEqual(['pos.sell', 'reports.view', 'stock.manage']);
  });
});

describe('AuthorizationService.hasAllPermissions', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: AuthorizationService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new AuthorizationService(prisma as unknown as PrismaService);
  });

  it('returns true without querying the database when no permission is required', async () => {
    const result = await service.hasAllPermissions('user-1', 'est-1', []);
    expect(result).toBe(true);
    expect(prisma.userEstablishmentRole.findMany).not.toHaveBeenCalled();
  });

  it('returns false when at least one required permission is missing', async () => {
    prisma.userEstablishmentRole.findMany.mockResolvedValue([
      { role: { rolePermissions: [{ permission: { code: 'stock.manage' } }] } },
    ]);
    const result = await service.hasAllPermissions('user-1', 'est-1', ['stock.manage', 'cash.manage']);
    expect(result).toBe(false);
  });

  it('returns true only when every required permission is granted', async () => {
    prisma.userEstablishmentRole.findMany.mockResolvedValue([
      { role: { rolePermissions: [{ permission: { code: 'stock.manage' } }, { permission: { code: 'cash.manage' } }] } },
    ]);
    const result = await service.hasAllPermissions('user-1', 'est-1', ['stock.manage', 'cash.manage']);
    expect(result).toBe(true);
  });
});
