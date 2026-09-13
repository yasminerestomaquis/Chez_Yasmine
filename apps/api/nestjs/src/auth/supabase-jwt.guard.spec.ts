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
  const prismaMock = { userProfile: { update: vi.fn().mockResolvedValue({}) } };

  beforeEach(() => {
    process.env.SUPABASE_URL = 'https://tsebsulvhgttdwtgqfoj.supabase.co';
    jwtVerifyMock.mockReset();
    prismaMock.userProfile.update.mockReset().mockResolvedValue({});
  });

  it('rejects a request with no Authorization header', async () => {
    const guard = new SupabaseJwtGuard(prismaMock as never);
    await expect(guard.canActivate(contextWithHeader())).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects a header that is not a Bearer token', async () => {
    const guard = new SupabaseJwtGuard(prismaMock as never);
    await expect(guard.canActivate(contextWithHeader('Basic abc123'))).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects a token that fails verification', async () => {
    jwtVerifyMock.mockRejectedValueOnce(new Error('signature invalide'));
    const guard = new SupabaseJwtGuard(prismaMock as never);
    await expect(guard.canActivate(contextWithHeader('Bearer bad.token.value'))).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it('attaches the decoded payload as request.user on success', async () => {
    const payload = { sub: 'user-1', email: 'yasmine@example.com', role: 'authenticated' };
    jwtVerifyMock.mockResolvedValueOnce({ payload });

    const guard = new SupabaseJwtGuard(prismaMock as never);
    const request: { headers: Record<string, string>; user?: unknown; supabaseAccessToken?: string } = {
      headers: { authorization: 'Bearer good.token.value' },
    };
    const context = {
      switchToHttp: () => ({ getRequest: () => request }),
    } as unknown as ExecutionContext;

    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(request.user).toEqual(payload);
    expect(request.supabaseAccessToken).toBe('good.token.value');
    expect(jwtVerifyMock).toHaveBeenCalledWith('good.token.value', expect.anything(), {
      issuer: 'https://tsebsulvhgttdwtgqfoj.supabase.co/auth/v1',
      audience: 'authenticated',
    });
  });

  it('records lastSeenAt for the authenticated user on success (best-effort, never awaited)', async () => {
    const payload = { sub: 'user-lastseen-1', email: 'a@example.com', role: 'authenticated' };
    jwtVerifyMock.mockResolvedValueOnce({ payload });
    const guard = new SupabaseJwtGuard(prismaMock as never);

    await guard.canActivate(contextWithHeader('Bearer good.token.value'));
    // recordLastSeen n'est jamais attendu par canActivate (best-effort) —
    // laisser le microtask en cours se vider avant de vérifier l'appel.
    await Promise.resolve();

    expect(prismaMock.userProfile.update).toHaveBeenCalledWith({
      where: { id: 'user-lastseen-1' },
      data: { lastSeenAt: expect.any(Date) },
    });
  });

  it('throttles repeated writes for the same user within 60s', async () => {
    const payload = { sub: 'user-lastseen-2', email: 'b@example.com', role: 'authenticated' };
    jwtVerifyMock.mockResolvedValue({ payload });
    const guard = new SupabaseJwtGuard(prismaMock as never);

    await guard.canActivate(contextWithHeader('Bearer good.token.value'));
    await guard.canActivate(contextWithHeader('Bearer good.token.value'));
    await Promise.resolve();

    expect(prismaMock.userProfile.update).toHaveBeenCalledTimes(1);
  });

  it('never fails authentication even if the lastSeenAt write rejects', async () => {
    const payload = { sub: 'user-lastseen-3', email: 'c@example.com', role: 'authenticated' };
    jwtVerifyMock.mockResolvedValueOnce({ payload });
    prismaMock.userProfile.update.mockReset().mockRejectedValue(new Error('db down'));
    const guard = new SupabaseJwtGuard(prismaMock as never);

    await expect(guard.canActivate(contextWithHeader('Bearer good.token.value'))).resolves.toBe(true);
  });
});
