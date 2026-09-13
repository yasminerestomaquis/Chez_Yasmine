import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import type { Request } from 'express';
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from 'jose';
import { PrismaService } from '../prisma/prisma.service.js';

export interface SupabaseUser extends JWTPayload {
  sub: string;
  email?: string;
  role?: string;
  user_metadata?: Record<string, unknown>;
}

declare module 'express' {
  interface Request {
    user?: SupabaseUser;
    /** The raw bearer token, kept so downstream services (e.g. Storage uploads) can act as this user rather than a service role. */
    supabaseAccessToken?: string;
  }
}

/**
 * Verifies the `Authorization: Bearer <jwt>` header against the Supabase
 * project's JWKS (asymmetric signing keys) — no shared secret involved.
 * On success, attaches the decoded token as `request.user`.
 */
/** En dessous de ce délai depuis la dernière écriture connue, on ne réécrit pas `lastSeenAt` — évite une requête UPDATE sur chaque appel API (une page en charge souvent plusieurs en parallèle) alors que ce module Utilisateurs n'a de toute façon pas besoin d'une précision à la seconde. */
const LAST_SEEN_WRITE_THROTTLE_MS = 60_000;

@Injectable()
export class SupabaseJwtGuard implements CanActivate {
  private static jwks: ReturnType<typeof createRemoteJWKSet> | null = null;
  /** En mémoire du process, pas en base — un redémarrage réécrit juste une fois de plus que nécessaire, sans conséquence. */
  private static lastSeenWrites = new Map<string, number>();

  constructor(private readonly prisma: PrismaService) {}

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
      request.supabaseAccessToken = token;
      this.recordLastSeen(payload.sub as string);
      return true;
    } catch {
      throw new UnauthorizedException('Jeton d\'authentification invalide ou expiré');
    }
  }

  /**
   * Best-effort, jamais attendu ni capable de faire échouer la requête —
   * une authentification ne doit jamais dépendre de la réussite de cette
   * écriture annexe. Voir docs/api/users.md pour comment ce champ nourrit
   * l'indicateur "connecté" du module Utilisateurs.
   */
  private recordLastSeen(userId: string): void {
    try {
      const lastWrite = SupabaseJwtGuard.lastSeenWrites.get(userId) ?? 0;
      const now = Date.now();
      if (now - lastWrite < LAST_SEEN_WRITE_THROTTLE_MS) return;
      SupabaseJwtGuard.lastSeenWrites.set(userId, now);
      this.prisma.userProfile
        .update({ where: { id: userId }, data: { lastSeenAt: new Date(now) } })
        .catch(() => {
          // Le profil peut ne pas encore exister (inscription en cours) ou la
          // base être momentanément indisponible — sans conséquence ici.
        });
    } catch {
      // Ne doit jamais empêcher l'authentification elle-même de réussir.
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
