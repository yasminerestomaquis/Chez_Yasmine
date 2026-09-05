import type { CallHandler, ExecutionContext, NestInterceptor } from '@nestjs/common';
import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import type { Observable } from 'rxjs';
import { map } from 'rxjs';

/**
 * Prisma's Decimal serializes to a JSON *string* ("1500.50"), never a JSON
 * number (confirmed directly: `JSON.stringify({ total: new Decimal('1500.5') })`
 * → `{"total":"1500.5"}`). Every Flutter model in this app parses amounts
 * with `(json['x'] as num).toDouble()`, which throws on a string. Rather
 * than adding a string-or-num branch to every model already written
 * (Phases 5-11) and every one still to come, every response is walked once
 * here and any Decimal is converted to a plain number before Express
 * serializes it.
 *
 * `Decimal` is only re-exported as `Prisma.Decimal` in this client's type
 * declarations (a bare top-level `Decimal` import type-checks against
 * nothing, even though it happens to exist at runtime) — use the namespaced
 * form here since this file is part of the real `nest build` compile.
 */
@Injectable()
export class DecimalTransformInterceptor implements NestInterceptor {
  intercept(_context: ExecutionContext, next: CallHandler): Observable<unknown> {
    return next.handle().pipe(map((value) => transformDecimals(value)));
  }
}

export function transformDecimals(value: unknown): unknown {
  if (value instanceof Prisma.Decimal) {
    return value.toNumber();
  }
  if (value instanceof Date) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map(transformDecimals);
  }
  if (value && typeof value === 'object') {
    const result: Record<string, unknown> = {};
    for (const [key, val] of Object.entries(value)) {
      result[key] = transformDecimals(val);
    }
    return result;
  }
  return value;
}
