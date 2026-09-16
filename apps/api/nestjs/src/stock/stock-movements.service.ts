import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import type { CreateStockMovementDto } from './dto/create-stock-movement.dto.js';
import { applyStockMovement, isLowStock } from './stock-math.js';

const MOVEMENT_TYPE_LABELS: Record<string, string> = { in: 'Entrée', out: 'Sortie', adjustment: 'Correction' };

@Injectable()
export class StockMovementsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly activityNotifier: ActivityNotifierService,
  ) {}

  private async getProductOrThrow(establishmentId: string, productId: string) {
    const product = await this.prisma.product.findFirst({
      where: { id: productId, establishmentId },
      include: { category: { select: { hasVariablePricing: true } } },
    });
    if (!product) {
      throw new NotFoundException('Produit introuvable pour cet établissement');
    }
    return product;
  }

  /**
   * Entrée ('in') sur une catégorie à prix variable (Poulets, Poissons,
   * Plats africains) : ces produits n'ont aucun flux d'achat automatisé
   * (contrairement aux catégories à prix par casier, approvisionnées via
   * Achats), donc un N° de marché doit être fourni et correspondre à une
   * dépense "Marché" déjà enregistrée pour l'établissement — c'est ce qui
   * permet à `computeFifoLots`/`ChartsService.stockLots` de rattacher le lot
   * créé à ce marché (voir docs/api/charts.md). Le motif stocké reprend le
   * même gabarit que `PurchasesService` ("Commande n°X") pour rester
   * parsable par la même expression régulière.
   */
  private resolveReason(
    dto: CreateStockMovementDto,
    hasVariablePricing: boolean,
  ): string | undefined {
    if (dto.type !== 'in' || !hasVariablePricing) return dto.reason;
    if (!dto.marketNumber) {
      throw new BadRequestException('N° de marché requis pour une entrée de stock dans cette catégorie');
    }
    return `Marché n°${dto.marketNumber}${dto.reason ? ` — ${dto.reason}` : ''}`;
  }

  async create(establishmentId: string, productId: string, userId: string, dto: CreateStockMovementDto) {
    // Idempotent replay — see SalesService.create for the same pattern.
    if (dto.id) {
      const existing = await this.prisma.stockMovement.findFirst({ where: { id: dto.id, productId } });
      if (existing) return existing;
    }

    const product = await this.getProductOrThrow(establishmentId, productId);
    const hasVariablePricing = product.category?.hasVariablePricing ?? false;

    if (dto.type === 'in' && hasVariablePricing && dto.marketNumber) {
      const market = await this.prisma.expense.findFirst({
        where: { establishmentId, category: 'Marché', marketNumber: dto.marketNumber },
        select: { id: true },
      });
      if (!market) {
        throw new BadRequestException(`Aucun marché n°${dto.marketNumber} enregistré pour cet établissement`);
      }
    }
    const reason = this.resolveReason(dto, hasVariablePricing);

    let nextQuantity: number;
    try {
      nextQuantity = applyStockMovement(product.stockQuantity.toNumber(), dto);
    } catch (error) {
      throw new BadRequestException(error instanceof Error ? error.message : 'Mouvement de stock invalide');
    }

    const [, movement] = await this.prisma.$transaction([
      this.prisma.product.update({ where: { id: productId }, data: { stockQuantity: nextQuantity } }),
      this.prisma.stockMovement.create({
        data: { id: dto.id, productId, type: dto.type, quantity: dto.quantity, reason, createdBy: userId },
      }),
    ]);
    await this.activityNotifier.notify(
      establishmentId,
      userId,
      'Mouvement de stock',
      `${MOVEMENT_TYPE_LABELS[dto.type] ?? dto.type} — ${product.name} : ${dto.quantity}${dto.reason ? ` (${dto.reason})` : ''}`,
    );
    return movement;
  }

  async listForProduct(establishmentId: string, productId: string) {
    await this.getProductOrThrow(establishmentId, productId);
    return this.prisma.stockMovement.findMany({ where: { productId }, orderBy: { createdAt: 'desc' } });
  }

  /**
   * Products at or below their alert threshold. Comparing two columns of the
   * same row (stockQuantity vs minStock) isn't expressible in a plain Prisma
   * `where`, so this filters in application code — fine at MVP catalog
   * sizes; revisit with a raw query or a view if that stops being true.
   */
  async listLowStockAlerts(establishmentId: string) {
    const products = await this.prisma.product.findMany({
      where: { establishmentId, status: 'active', minStock: { gt: 0 } },
      select: { id: true, name: true, stockQuantity: true, minStock: true },
    });
    return products
      .filter((p) => isLowStock(p.stockQuantity.toNumber(), p.minStock.toNumber()))
      .map((p) => ({ id: p.id, name: p.name, stockQuantity: p.stockQuantity.toNumber(), minStock: p.minStock.toNumber() }));
  }

  /**
   * Totaux cumulés par produit pour le module Stock (demande utilisateur du
   * 2026-09-16) : reçue (mouvements `in`), consommée (`sale`, vendue en
   * caisse/salle — délibérément différente de `out`, qui reste une sortie
   * manuelle distincte, ex. usage interne, jamais confondue avec une vente),
   * perte (`loss`, écrite par le module Pertes). `adjustment` en est
   * volontairement exclu : c'est une correction du stock affiché, pas un
   * flux réel entré/sorti. Un seul `groupBy` pour tout l'établissement
   * plutôt qu'un aller-retour par produit (`listForProduct`) — le listing
   * Stock affiche potentiellement tout le catalogue en une fois.
   */
  async listMovementTotals(establishmentId: string) {
    const rows = await this.prisma.stockMovement.groupBy({
      by: ['productId', 'type'],
      where: { product: { establishmentId } },
      _sum: { quantity: true },
    });

    const byProduct = new Map<string, { received: number; consumed: number; lost: number }>();
    for (const row of rows) {
      const entry = byProduct.get(row.productId) ?? { received: 0, consumed: 0, lost: 0 };
      const quantity = row._sum.quantity?.toNumber() ?? 0;
      if (row.type === 'in') entry.received += quantity;
      else if (row.type === 'sale') entry.consumed += quantity;
      else if (row.type === 'loss') entry.lost += quantity;
      byProduct.set(row.productId, entry);
    }

    return Array.from(byProduct.entries()).map(([productId, totals]) => ({ productId, ...totals }));
  }
}
