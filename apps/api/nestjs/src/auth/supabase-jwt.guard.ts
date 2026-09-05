import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import type { Request } from 'express';
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from 'jose';

export interface SupabaseUser extends JWTPayload {
  sub: string;
  email?: string;
  role?: string;
  user_metadata?: Record<string, unknown>;
}

declare module 'express' {
  interface Request {
    user?: SupabaseUser;
  }
}

/**
 * Verifies the `Authorization: Bearer <jwt>` header against the Supabase
 * project's JWKS (asymmetric signing keys) — no shared secret involved.
 * On success, attaches the decoded token as `request.user`.
 */
@Injectable()
export class SupabaseJwtGuard implements CanActivate {
  private static jwks: ReturnType<typeof createRemoteJWKSet> | null = null;

  private static getJwks(): ReturnType<typeof createRemoteJWKSet> {
    if (!SupabaseJwtGuard.jwks) {
      const supabaseUrl = process.env.SUPABASE_URL;
      if (!supabaseUrl) {
        throw new Error('SUPABASE_URL is not configured');
      }
      SupabaseJwtGuard.jwks = createRemoteJWKSet(new URL(`${supabaseUrl}/auth/v1/.well-known/jwks.json`));
    }
    return SupabaseJwtGuard.jwks;
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request>();
    const token = this.extractBearerToken(request);
    if (!token) {
      throw new UnauthorizedException('Jeton d\'authentification manquant');
    }

    const supabaseUrl = process.env.SUPABASE_URL;
    try {
      const { payload } = await jwtVerify(token, SupabaseJwtGuard.getJwks(), {
        issuer: `${supabaseUrl}/auth/v1`,
        audience: 'authenticated',
      });
      request.user = payload as SupabaseUser;
      return true;
    } catch {
      throw new UnauthorizedException('Jeton d\'authentification invalide ou expiré');
    }
  }

  private extractBearerToken(request: Request): string | null {
    const header = request.headers.authorization;
    if (!header) return null;
    const [scheme, token] = header.split(' ');
    if (scheme !== 'Bearer' || !token) return null;
    return token;
  }
}
