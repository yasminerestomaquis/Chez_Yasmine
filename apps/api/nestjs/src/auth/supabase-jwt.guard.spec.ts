import type { ExecutionContext } from '@nestjs/common';
import { UnauthorizedException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const { jwtVerifyMock, createRemoteJWKSetMock } = vi.hoisted(() => ({
  jwtVerifyMock: vi.fn(),
  createRemoteJWKSetMock: vi.fn(() => vi.fn()),
}));

vi.mock('jose', () => ({
  createRemoteJWKSet: createRemoteJWKSetMock,
  jwtVerify: jwtVerifyMock,
}));

// Imported after the mock so the guard picks up the mocked `jose`.
const { SupabaseJwtGuard } = await import('./supabase-jwt.guard.js');

function contextWithHeader(authorization?: string): ExecutionContext {
  const request: { headers: Record<string, string>; user?: unknown } = {
    headers: authorization ? { authorization } : {},
  };
  return {
    switchToHttp: () => ({ getRequest: () => request }),
  } as unknown as ExecutionContext;
}

describe('SupabaseJwtGuard', () => {
  beforeEach(() => {
    process.env.SUPABASE_URL = 'https://tsebsulvhgttdwtgqfoj.supabase.co';
    jwtVerifyMock.mockReset();
  });

  it('rejects a request with no Authorization header', async () => {
    const guard = new SupabaseJwtGuard();
    await expect(guard.canActivate(contextWithHeader())).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects a header that is not a Bearer token', async () => {
    const guard = new SupabaseJwtGuard();
    await expect(guard.canActivate(contextWithHeader('Basic abc123'))).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects a token that fails verification', async () => {
    jwtVerifyMock.mockRejectedValueOnce(new Error('signature invalide'));
    const guard = new SupabaseJwtGuard();
    await expect(guard.canActivate(contextWithHeader('Bearer bad.token.value'))).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('attaches the decoded payload as request.user on success', async () => {
    const payload = { sub: 'user-1', email: 'yasmine@example.com', role: 'authenticated' };
    jwtVerifyMock.mockResolvedValueOnce({ payload });

    const guard = new SupabaseJwtGuard();
    const request: { headers: Record<string, string>; user?: unknown } = {
      headers: { authorization: 'Bearer good.token.value' },
    };
    const context = {
      switchToHttp: () => ({ getRequest: () => request }),
    } as unknown as ExecutionContext;

    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(request.user).toEqual(payload);
    expect(jwtVerifyMock).toHaveBeenCalledWith('good.token.value', expect.anything(), {
      issuer: 'https://tsebsulvhgttdwtgqfoj.supabase.co/auth/v1',
      audience: 'authenticated',
    });
  });
});
