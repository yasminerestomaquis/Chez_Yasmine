import type { ExecutionContext } from '@nestjs/common';
import { ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { AuthorizationService } from './authorization.service.js';
import { PermissionsGuard } from './permissions.guard.js';

function makeContext(user: { sub?: string } | undefined, params: Record<string, string>): ExecutionContext {
  const request = { user, params };
  return {
    switchToHttp: () => ({ getRequest: () => request }),
    getHandler: () => ({}),
    getClass: () => ({}),
  } as unknown as ExecutionContext;
}

describe('PermissionsGuard', () => {
  let reflector: Reflector;
  let authorization: { hasAllPermissions: ReturnType<typeof vi.fn> };
  let guard: PermissionsGuard;

  beforeEach(() => {
    reflector = new Reflector();
    authorization = { hasAllPermissions: vi.fn() };
    guard = new PermissionsGuard(reflector, authorization as unknown as AuthorizationService);
  });

  it('allows the request when the route requires no permissions', async () => {
    vi.spyOn(reflector, 'getAllAndOverride').mockReturnValue(undefined);
    const context = makeContext({ sub: 'user-1' }, { establishmentId: 'est-1' });
    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(authorization.hasAllPermissions).not.toHaveBeenCalled();
  });

  it('rejects when the user or establishmentId is missing from the request', async () => {
    vi.spyOn(reflector, 'getAllAndOverride').mockReturnValue(['settings.manage']);
    const context = makeContext(undefined, { establishmentId: 'est-1' });
    await expect(guard.canActivate(context)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('rejects when the user lacks the required permission', async () => {
    vi.spyOn(reflector, 'getAllAndOverride').mockReturnValue(['settings.manage']);
    authorization.hasAllPermissions.mockResolvedValue(false);
    const context = makeContext({ sub: 'user-1' }, { establishmentId: 'est-1' });
    await expect(guard.canActivate(context)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('allows the request when the user has the required permission', async () => {
    vi.spyOn(reflector, 'getAllAndOverride').mockReturnValue(['settings.manage']);
    authorization.hasAllPermissions.mockResolvedValue(true);
    const context = makeContext({ sub: 'user-1' }, { establishmentId: 'est-1' });
    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(authorization.hasAllPermissions).toHaveBeenCalledWith('user-1', 'est-1', ['settings.manage']);
  });
});
