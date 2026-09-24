import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CreateProductDto } from './dto/create-product.dto.js';
import type { UpdateProductDto } from './dto/update-product.dto.js';

@Injectable()
export class ProductsService {
  constructor(private readonly prisma: PrismaService) {}

  list(establishmentId: string) {
    return this.prisma.product.findMany({
      where: { establishmentId },
      include: { images: { orderBy: { position: 'asc' } }, category: true },
      orderBy: { name: 'asc' },
    });
  }

  async get(establishmentId: string, productId: string) {
    const product = await this.prisma.product.findFirst({
      where: { id: productId, establishmentId },
      include: { images: { orderBy: { position: 'asc' } }, category: true },
    });
    if (!product) {
      throw new NotFoundException('Produit introuvable pour cet établissement');
    }
    return product;
  }

  /**
   * Le stock initial saisi à la création (`dto.stockQuantity`) écrit
   * directement `product.stockQuantity`, sans mouvement de stock associé —
   * jusqu'ici. Ce stock restait donc invisible pour `computeFifoLots`
   * (`ChartsService.stockLots`, Graphiques > Stock), qui ne reconstruit les
   * lots qu'à partir de `StockMovement` : la somme des lots d'un produit créé
   * avec un stock initial non nul ne pouvait jamais rejoindre son
   * `stockQuantity` réel (écart constaté en production sur ~40% des produits
   * à prix par casier, 2026-09-25). Un mouvement `'in'` compagnon (sans N° de
   * commande — ce stock n'a jamais été reçu via une commande) corrige ça ; il
   * devient, comme tout mouvement sans référence pour une catégorie gérée par
   * lots, rattaché au dernier lot visible ou un lot synthétique (voir le
   * correctif dans `ChartsService.stockLots`).
   */
  async create(establishmentId: string, userId: string, dto: CreateProductDto) {
    await this.assertReferencesBelongToEstablishment(establishmentId, dto.categoryId, dto.supplierId);
    const hasVariablePricing = await this.categoryHasVariablePricing(establishmentId, dto.categoryId);
    // requiresPriceAtSale : produit de catégorie fixe (achat à prix connu,
    // ex. Gbêlê) dont le prix de VENTE varie néanmoins à chaque vente —
    // distinct de hasVariablePricing, qui supprime aussi le prix d'achat et
    // exige un numéro de marché à la livraison (voir schema.prisma).
    const manualPriceAtSale = hasVariablePricing || dto.requiresPriceAtSale === true;
    if (!manualPriceAtSale && dto.salePrice == null) {
      throw new BadRequestException('Le prix de vente est requis pour cette catégorie');
    }
    const initialStock = dto.stockQuantity ?? 0;
    return this.prisma.$transaction(async (tx) => {
      const product = await tx.product.create({
        data: {
          establishmentId,
          name: dto.name,
          categoryId: dto.categoryId,
          supplierId: dto.supplierId,
          reference: dto.reference,
          description: dto.description,
          barcode: dto.barcode,
          qrCode: dto.qrCode,
          unit: dto.unit,
          // Catégorie à prix variable (ex. Poulets/Poissons/Plats africains) :
          // jamais de prix d'achat/de vente dans le catalogue, quoi qu'envoie
          // le client — prix de vente saisi en caisse, achat suivi via la
          // dépense "Marché" (voir docs/api/catalog.md).
          purchasePrice: hasVariablePricing ? null : dto.purchasePrice,
          salePrice: manualPriceAtSale ? null : dto.salePrice,
          unitSalePrice: hasVariablePricing ? null : dto.unitSalePrice,
          requiresPriceAtSale: dto.requiresPriceAtSale ?? false,
          referenceSalePrice: dto.requiresPriceAtSale ? dto.referenceSalePrice : null,
          bottlesPerCase: dto.bottlesPerCase,
          purchasePricePerCase: dto.purchasePricePerCase,
          vatRate: dto.vatRate,
          minStock: dto.minStock,
          stockQuantity: initialStock,
          status: dto.status ?? 'active',
        },
      });
      if (initialStock > 0) {
        await tx.stockMovement.create({
          data: { productId: product.id, type: 'in', quantity: initialStock, reason: 'Stock initial à la création du produit', createdBy: userId },
        });
      }
      return product;
    });
  }

  async update(establishmentId: string, productId: string, dto: UpdateProductDto) {
    const existing = await this.prisma.product.findFirst({ where: { id: productId, establishmentId } });
    if (!existing) {
      throw new NotFoundException('Produit introuvable pour cet établissement');
    }
    await this.assertReferencesBelongToEstablishment(establishmentId, dto.categoryId, dto.supplierId);
    const effectiveCategoryId = dto.categoryId !== undefined ? dto.categoryId : existing.categoryId;
    const hasVariablePricing = await this.categoryHasVariablePricing(establishmentId, effectiveCategoryId);
    const nextRequiresPriceAtSale =
      dto.requiresPriceAtSale !== undefined ? dto.requiresPriceAtSale : existing.requiresPriceAtSale;
    const manualPriceAtSale = hasVariablePricing || nextRequiresPriceAtSale;

    const data: Prisma.ProductUpdateManyMutationInput = { ...dto };
    if (hasVariablePricing) {
      data.purchasePrice = null;
      data.salePrice = null;
      data.unitSalePrice = null;
    } else if (manualPriceAtSale) {
      data.salePrice = null;
    } else {
      const nextSalePrice = dto.salePrice !== undefined ? dto.salePrice : existing.salePrice?.toNumber();
      if (nextSalePrice == null) {
        throw new BadRequestException('Le prix de vente est requis pour cette catégorie');
      }
    }
    if (!nextRequiresPriceAtSale) {
      data.referenceSalePrice = null;
    }

    const { count } = await this.prisma.product.updateMany({
      where: { id: productId, establishmentId },
      data,
    });
    if (count === 0) {
      throw new NotFoundException('Produit introuvable pour cet établissement');
    }
    return this.get(establishmentId, productId);
  }

  /**
   * Suppression physique quand c'est possible ; sinon (produit référencé par
   * des ventes/achats/commandes/mouvements de stock historiques — ces
   * relations ne sont volontairement pas en cascade, voir le schéma) on
   * désactive le produit à la place (`status: 'inactive'`) plutôt que
   * d'échouer avec une erreur de contrainte de clé étrangère brute. Un
   * produit inactif n'apparaît plus dans le catalogue/la caisse mais son
   * historique (ventes passées, rapports) reste intact.
   */
  async remove(establishmentId: string, productId: string): Promise<{ softDeleted: boolean }> {
    try {
      const { count } = await this.prisma.product.deleteMany({ where: { id: productId, establishmentId } });
      if (count === 0) {
        throw new NotFoundException('Produit introuvable pour cet établissement');
      }
      return { softDeleted: false };
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2003') {
        const { count } = await this.prisma.product.updateMany({
          where: { id: productId, establishmentId },
          data: { status: 'inactive' },
        });
        if (count === 0) {
          throw new NotFoundException('Produit introuvable pour cet établissement');
        }
        return { softDeleted: true };
      }
      throw error;
    }
  }

  private async categoryHasVariablePricing(establishmentId: string, categoryId?: string | null): Promise<boolean> {
    if (!categoryId) return false;
    const category = await this.prisma.category.findFirst({ where: { id: categoryId, establishmentId } });
    return category?.hasVariablePricing ?? false;
  }

  private async assertReferencesBelongToEstablishment(
    establishmentId: string,
    categoryId?: string,
    supplierId?: string,
  ): Promise<void> {
    if (categoryId) {
      const category = await this.prisma.category.findFirst({ where: { id: categoryId, establishmentId } });
      if (!category) {
        throw new BadRequestException("La catégorie indiquée n'appartient pas à cet établissement");
      }
    }
    if (supplierId) {
      const supplier = await this.prisma.supplier.findFirst({ where: { id: supplierId, establishmentId } });
      if (!supplier) {
        throw new BadRequestException("Le fournisseur indiqué n'appartient pas à cet établissement");
      }
    }
  }
}
