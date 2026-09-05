import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';

@Injectable()
export class AuthorizationService {
  constructor(private readonly prisma: PrismaService) {}

  /** Permission codes granted to `userId` on `establishmentId`, across all its roles there. */
  async getPermissionCodes(userId: string, establishmentId: string): Promise<Set<string>> {
    const links = await this.prisma.userEstablishmentRole.findMany({
      where: { userId, establishmentId },
      select: { role: { select: { rolePermissions: { select: { permission: { select: { code: true } } } } } } },
    });

    const codes = new Set<string>();
    for (const link of links) {
      for (const rp of link.role.rolePermissions) {
        codes.add(rp.permission.code);
      }
    }
    return codes;
  }

  async hasAllPermissions(userId: string, establishmentId: string, required: string[]): Promise<boolean> {
    if (required.length === 0) return true;
    const granted = await this.getPermissionCodes(userId, establishmentId);
    return required.every((code) => granted.has(code));
  }
}
