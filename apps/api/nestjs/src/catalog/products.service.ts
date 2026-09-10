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

  async create(establishmentId: string, dto: CreateProductDto) {
    await this.assertReferencesBelongToEstablishment(establishmentId, dto.categoryId, dto.supplierId);
    const hasVariablePricing = await this.categoryHasVariablePricing(establishmentId, dto.categoryId);
    if (!hasVariablePricing && dto.salePrice == null) {
      throw new BadRequestException('Le prix de vente est requis pour cette catégorie');
    }
    return this.prisma.product.create({
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
        salePrice: hasVariablePricing ? null : dto.salePrice,
        bottlesPerCase: dto.bottlesPerCase,
        purchasePricePerCase: dto.purchasePricePerCase,
        vatRate: dto.vatRate,
        minStock: dto.minStock,
        stockQuantity: dto.stockQuantity ?? 0,
        status: dto.status ?? 'active',
      },
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

    const data: Prisma.ProductUpdateManyMutationInput = { ...dto };
    if (hasVariablePricing) {
      // `salePrice` reste toujours nul (saisi en caisse à chaque vente).
      // `purchasePrice` n'est volontairement PAS forcé ici (ne pas ajouter
      // `data.purchasePrice = null`) : ces catégories n'ont aucun prix
      // d'achat catalogue, mais PurchasesService y écrit un instantané du
      // dernier prix d'achat payé (voir docs/api/purchasing.md) — l'écraser
      // à chaque modification du produit (même un simple changement de nom)
      // effacerait ce coût et casserait les rapports/graphiques par catégorie.
      data.salePrice = null;
    } else {
      const nextSalePrice = dto.salePrice !== undefined ? dto.salePrice : existing.salePrice?.toNumber();
      if (nextSalePrice == null) {
        throw new BadRequestException('Le prix de vente est requis pour cette catégorie');
      }
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
