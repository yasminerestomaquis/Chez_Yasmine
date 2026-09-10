import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service.js';
import { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import type { CreatePurchaseDto, PurchaseItemDto } from './dto/create-purchase.dto.js';
import type { UpdatePurchaseDto } from './dto/update-purchase.dto.js';

type Tx = Prisma.TransactionClient;

/**
 * Le timeout interactif par défaut de Prisma (5 s) est trop court dès qu'une
 * commande compte une quinzaine de lignes ou plus : chaque ligne coûte
 * plusieurs allers-retours séquentiels (lecture + écriture stock + écriture
 * mouvement), et le tout s'exécute dans UNE seule transaction. Constaté en
 * conditions réelles (2026-09-10) : une commande de 15 articles dépassait
 * systématiquement les 5 s et échouait en 500 générique (le timeout Prisma
 * n'est pas une HttpException, donc NestJS ne peut pas le traduire en erreur
 * lisible) — reproduit avec un compte de démonstration jetable avant ce
 * correctif. 30 s laisse une marge confortable pour des commandes nettement
 * plus grandes.
 */
const PURCHASE_TRANSACTION_OPTIONS = { timeout: 30_000 };

const purchaseInclude = {
  supplier: true,
  items: {
    include: { product: { include: { images: { orderBy: { position: 'asc' } } } } },
  },
} satisfies Prisma.PurchaseInclude;

interface ResolvedLine {
  productId: string;
  productName: string;
  /** Nulles pour une ligne "prix variable" — voir PurchaseItem dans schema.prisma. */
  casesOrdered: number | null;
  bottlesPerCase: number | null;
  purchasePricePerCase: number | null;
  quantity: number; // casesOrdered * bottlesPerCase (casier) ou quantityOrdered (prix variable) — ce qui bouge réellement le stock
  unitPrice: number; // purchasePricePerCase / bottlesPerCase (casier) ou unitPurchasePrice (prix variable)
  /**
   * Prix variable uniquement : ce produit n'a aucun `purchasePrice` fixé
   * dans le Catalogue (toujours nul pour ces catégories), donc chaque achat
   * devient la seule source de coût pour les rapports/graphiques — écrasé
   * par le plus récent, comme le reste de l'application qui ne connaît que
   * le coût d'achat "actuel" du produit (pas de coût historique par vente).
   */
  purchasePriceToSnapshot: number | null;
}

@Injectable()
export class PurchasesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly activityNotifier: ActivityNotifierService,
  ) {}

  list(establishmentId: string) {
    return this.prisma.purchase.findMany({
      where: { establishmentId },
      include: purchaseInclude,
      orderBy: { orderDate: 'desc' },
    });
  }

  async get(establishmentId: string, purchaseId: string) {
    const purchase = await this.prisma.purchase.findFirst({
      where: { id: purchaseId, establishmentId },
      include: purchaseInclude,
    });
    if (!purchase) {
      throw new NotFoundException('Achat introuvable pour cet établissement');
    }
    return purchase;
  }

  /**
   * Commande par casier (Bières, Vins, Sucreries — voir docs/api/purchasing.md) :
   * seuls les produits d'une catégorie hasCasePricing sont acceptés ;
   * bottlesPerCase/purchasePricePerCase sont toujours dérivés du Catalogue
   * (jamais du client). Décision explicite de l'utilisateur (2026-09-09) :
   * le stock entre directement à la création, pas d'étape de réception
   * séparée pour ce flux (contrairement à receive() ci-dessous, conservé
   * pour les achats "classiques" existants).
   */
  async create(establishmentId: string, userId: string, dto: CreatePurchaseDto) {
    if (dto.supplierId) {
      const supplier = await this.prisma.supplier.findFirst({ where: { id: dto.supplierId, establishmentId } });
      if (!supplier) {
        throw new BadRequestException("Le fournisseur indiqué n'appartient pas à cet établissement");
      }
    }
    const lines = await this.resolveLines(establishmentId, dto.items);
    const total = lines.reduce((sum, l) => sum + l.quantity * l.unitPrice, 0);

    const purchase = await this.prisma.$transaction(async (tx) => {
      const created = await tx.purchase.create({
        data: {
          establishmentId,
          supplierId: dto.supplierId,
          orderNumber: dto.orderNumber,
          orderDate: dto.orderDate ? new Date(dto.orderDate) : undefined,
          status: 'received',
          total,
          items: {
            create: lines.map((l) => ({
              productId: l.productId,
              quantity: l.quantity,
              unitPrice: l.unitPrice,
              casesOrdered: l.casesOrdered,
              bottlesPerCase: l.bottlesPerCase,
              purchasePricePerCase: l.purchasePricePerCase,
            })),
          },
        },
        include: purchaseInclude,
      });
      for (const line of lines) {
        await this.applyStock(tx, line.productId, line.quantity, userId, `Commande n°${dto.orderNumber}`, line.purchasePriceToSnapshot);
      }
      return created;
    }, PURCHASE_TRANSACTION_OPTIONS);
    await this.activityNotifier.notify(
      establishmentId,
      'Achat reçu',
      `${purchase.supplier?.name ?? 'Fournisseur non renseigné'} — ${total.toLocaleString('fr-FR')} FCFA (${lines.length} article(s))`,
    );
    return purchase;
  }

  /** Remplace l'intégralité des lignes : annule l'effet stock des anciennes, applique les nouvelles. */
  async update(establishmentId: string, userId: string, purchaseId: string, dto: UpdatePurchaseDto) {
    const existing = await this.prisma.purchase.findFirst({
      where: { id: purchaseId, establishmentId },
      include: { items: true },
    });
    if (!existing) {
      throw new NotFoundException('Achat introuvable pour cet établissement');
    }
    if (dto.supplierId) {
      const supplier = await this.prisma.supplier.findFirst({ where: { id: dto.supplierId, establishmentId } });
      if (!supplier) {
        throw new BadRequestException("Le fournisseur indiqué n'appartient pas à cet établissement");
      }
    }
    const lines = await this.resolveLines(establishmentId, dto.items);
    const total = lines.reduce((sum, l) => sum + l.quantity * l.unitPrice, 0);
    const orderNumber = dto.orderNumber ?? existing.orderNumber;

    return this.prisma.$transaction(async (tx) => {
      for (const item of existing.items) {
        await this.reverseStock(tx, item.productId, item.quantity.toNumber(), userId, `Correction commande n°${orderNumber}`);
      }
      await tx.purchaseItem.deleteMany({ where: { purchaseId } });
      await tx.purchase.update({
        where: { id: purchaseId },
        data: {
          supplierId: dto.supplierId,
          orderNumber,
          orderDate: dto.orderDate ? new Date(dto.orderDate) : undefined,
          total,
          items: {
            create: lines.map((l) => ({
              productId: l.productId,
              quantity: l.quantity,
              unitPrice: l.unitPrice,
              casesOrdered: l.casesOrdered,
              bottlesPerCase: l.bottlesPerCase,
              purchasePricePerCase: l.purchasePricePerCase,
            })),
          },
        },
      });
      for (const line of lines) {
        await this.applyStock(tx, line.productId, line.quantity, userId, `Correction commande n°${orderNumber}`, line.purchasePriceToSnapshot);
      }
      return tx.purchase.findUniqueOrThrow({ where: { id: purchaseId }, include: purchaseInclude });
    }, PURCHASE_TRANSACTION_OPTIONS);
  }

  /** Annule l'effet stock de la commande (clampé à 0, jamais négatif) puis la supprime. */
  async remove(establishmentId: string, userId: string, purchaseId: string): Promise<void> {
    const existing = await this.prisma.purchase.findFirst({
      where: { id: purchaseId, establishmentId },
      include: { items: true },
    });
    if (!existing) {
      throw new NotFoundException('Achat introuvable pour cet établissement');
    }
    await this.prisma.$transaction(async (tx) => {
      for (const item of existing.items) {
        await this.reverseStock(
          tx,
          item.productId,
          item.quantity.toNumber(),
          userId,
          `Suppression commande n°${existing.orderNumber}`,
        );
      }
      await tx.purchase.delete({ where: { id: purchaseId } });
    }, PURCHASE_TRANSACTION_OPTIONS);
  }

  /** Retourne le prochain N° de commande suggéré pour un fournisseur (ou "aucun fournisseur") — simple convenance, jamais imposé côté serveur. */
  async nextOrderNumber(establishmentId: string, supplierId?: string): Promise<number> {
    const last = await this.prisma.purchase.findFirst({
      where: { establishmentId, supplierId: supplierId ?? null },
      orderBy: { orderNumber: 'desc' },
      select: { orderNumber: true },
    });
    return (last?.orderNumber ?? 0) + 1;
  }

  /** @deprecated Flux "achat classique" antérieur au module par casier (2026-09-09) — conservé pour les commandes `pending` existantes, jamais utilisé par le nouveau flux (qui crée directement en `received`). */
  async receive(establishmentId: string, purchaseId: string, userId: string) {
    const purchase = await this.prisma.purchase.findFirst({
      where: { id: purchaseId, establishmentId },
      include: { items: true },
    });
    if (!purchase) {
      throw new NotFoundException('Achat introuvable pour cet établissement');
    }
    if (purchase.status !== 'pending') {
      throw new ConflictException('Cet achat a déjà été reçu ou annulé');
    }

    const received = await this.prisma.$transaction(async (tx) => {
      for (const item of purchase.items) {
        const quantity = item.quantity.toNumber();
        await tx.product.update({ where: { id: item.productId }, data: { stockQuantity: { increment: quantity } } });
        await tx.stockMovement.create({
          data: { productId: item.productId, type: 'in', quantity, reason: `Réception achat ${purchase.id}`, createdBy: userId },
        });
      }
      return tx.purchase.update({
        where: { id: purchaseId },
        data: { status: 'received' },
        include: purchaseInclude,
      });
    }, PURCHASE_TRANSACTION_OPTIONS);
    await this.activityNotifier.notify(
      establishmentId,
      'Achat reçu',
      `${received.supplier?.name ?? 'Fournisseur non renseigné'} — ${received.total.toNumber().toLocaleString('fr-FR')} FCFA (${received.items.length} article(s))`,
    );
    return received;
  }

  /** @deprecated Voir receive() — ne s'applique qu'à une commande `pending`, jamais créée par le nouveau flux par casier. */
  async cancel(establishmentId: string, purchaseId: string) {
    const purchase = await this.prisma.purchase.findFirst({ where: { id: purchaseId, establishmentId } });
    if (!purchase) {
      throw new NotFoundException('Achat introuvable pour cet établissement');
    }
    if (purchase.status !== 'pending') {
      throw new ConflictException('Seul un achat en attente peut être annulé');
    }
    return this.prisma.purchase.update({ where: { id: purchaseId }, data: { status: 'cancelled' } });
  }

  /**
   * Valide et résout chaque ligne selon la catégorie réelle du produit :
   * - hasCasePricing (Bières, Vins, Sucreries) : nbre de casiers requis dans
   *   la requête, bottlesPerCase/purchasePricePerCase toujours dérivés du
   *   Catalogue, jamais acceptés du client (défense en profondeur).
   * - hasVariablePricing (Poulets, Poissons, Plats africains) : quantité
   *   achetée + prix d'achat unitaire requis dans la requête (aucune donnée
   *   de coût n'existe dans le Catalogue pour ces catégories — voir
   *   ProductsService, purchasePrice y est toujours nul).
   * - Toute autre catégorie : achat non pris en charge par ce module pour
   *   l'instant, rejeté explicitement.
   */
  private async resolveLines(establishmentId: string, items: PurchaseItemDto[]): Promise<ResolvedLine[]> {
    const productIds = [...new Set(items.map((i) => i.productId))];
    const products = await this.prisma.product.findMany({
      where: { id: { in: productIds }, establishmentId },
      include: { category: true },
    });
    if (products.length !== productIds.length) {
      throw new BadRequestException("Un ou plusieurs produits n'appartiennent pas à cet établissement");
    }
    const productById = new Map(products.map((p) => [p.id, p]));

    return items.map((item) => {
      const product = productById.get(item.productId)!;

      if (product.category?.hasCasePricing) {
        if (item.casesOrdered == null) {
          throw new BadRequestException(`${product.name} : nombre de casiers commandés requis`);
        }
        if (!product.bottlesPerCase || product.bottlesPerCase < 1) {
          throw new BadRequestException(`${product.name} : "Nbre de bouteilles par casier" non renseigné dans le Catalogue`);
        }
        if (product.purchasePricePerCase == null) {
          throw new BadRequestException(`${product.name} : "Prix d'achat par casier" non renseigné dans le Catalogue`);
        }
        const bottlesPerCase = product.bottlesPerCase;
        const purchasePricePerCase = product.purchasePricePerCase.toNumber();
        return {
          productId: product.id,
          productName: product.name,
          casesOrdered: item.casesOrdered,
          bottlesPerCase,
          purchasePricePerCase,
          quantity: item.casesOrdered * bottlesPerCase,
          unitPrice: purchasePricePerCase / bottlesPerCase,
          purchasePriceToSnapshot: null,
        };
      }

      if (product.category?.hasVariablePricing) {
        if (item.quantityOrdered == null) {
          throw new BadRequestException(`${product.name} : quantité achetée requise`);
        }
        if (item.unitPurchasePrice == null) {
          throw new BadRequestException(`${product.name} : prix d'achat unitaire requis`);
        }
        return {
          productId: product.id,
          productName: product.name,
          casesOrdered: null,
          bottlesPerCase: null,
          purchasePricePerCase: null,
          quantity: item.quantityOrdered,
          unitPrice: item.unitPurchasePrice,
          purchasePriceToSnapshot: item.unitPurchasePrice,
        };
      }

      throw new BadRequestException(
        `${product.name} n'appartient ni à une catégorie à prix par casier (Bières, Vins, Sucreries) ni à prix variable (Poulets, Poissons, Plats africains)`,
      );
    });
  }

  private async applyStock(
    tx: Tx,
    productId: string,
    quantity: number,
    userId: string,
    reason: string,
    purchasePriceToSnapshot?: number | null,
  ): Promise<void> {
    await tx.product.update({
      where: { id: productId },
      data: {
        stockQuantity: { increment: quantity },
        ...(purchasePriceToSnapshot != null ? { purchasePrice: purchasePriceToSnapshot } : {}),
      },
    });
    await tx.stockMovement.create({ data: { productId, type: 'in', quantity, reason, createdBy: userId } });
  }

  /** Décrémente sans jamais passer sous 0 — une correction/suppression ne doit pas faire échouer si une partie du stock a déjà été vendue depuis. */
  private async reverseStock(tx: Tx, productId: string, quantity: number, userId: string, reason: string): Promise<void> {
    const product = await tx.product.findUniqueOrThrow({ where: { id: productId } });
    const nextQuantity = Math.max(0, product.stockQuantity.toNumber() - quantity);
    await tx.product.update({ where: { id: productId }, data: { stockQuantity: nextQuantity } });
    await tx.stockMovement.create({ data: { productId, type: 'out', quantity, reason, createdBy: userId } });
  }
}
