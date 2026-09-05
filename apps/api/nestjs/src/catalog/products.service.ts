import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
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
        purchasePrice: dto.purchasePrice,
        salePrice: dto.salePrice,
        vatRate: dto.vatRate,
        minStock: dto.minStock,
        stockQuantity: dto.stockQuantity ?? 0,
        status: dto.status ?? 'active',
      },
    });
  }

  async update(establishmentId: string, productId: string, dto: UpdateProductDto) {
    await this.assertReferencesBelongToEstablishment(establishmentId, dto.categoryId, dto.supplierId);
    const { count } = await this.prisma.product.updateMany({
      where: { id: productId, establishmentId },
      data: dto,
    });
    if (count === 0) {
      throw new NotFoundException('Produit introuvable pour cet établissement');
    }
    return this.get(establishmentId, productId);
  }

  async remove(establishmentId: string, productId: string): Promise<void> {
    const { count } = await this.prisma.product.deleteMany({ where: { id: productId, establishmentId } });
    if (count === 0) {
      throw new NotFoundException('Produit introuvable pour cet établissement');
    }
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
