import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { PrismaService } from '../prisma/prisma.service.js';
import { IMAGE_VARIANT_SIZES, ImageProcessingService, type ImageVariantName } from '../storage/image-processing.service.js';
import { SupabaseStorageService } from '../storage/supabase-storage.service.js';

@Injectable()
export class ProductImagesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly imageProcessing: ImageProcessingService,
    private readonly storage: SupabaseStorageService,
  ) {}

  private async assertProductBelongsToEstablishment(establishmentId: string, productId: string) {
    const product = await this.prisma.product.findFirst({
      where: { id: productId, establishmentId },
      select: { id: true, establishment: { select: { organizationId: true } } },
    });
    if (!product) {
      throw new NotFoundException('Produit introuvable pour cet établissement');
    }
    return product;
  }

  async upload(
    accessToken: string,
    establishmentId: string,
    productId: string,
    file: { buffer: Buffer; mimetype: string },
  ) {
    const product = await this.assertProductBelongsToEstablishment(establishmentId, productId);
    await this.imageProcessing.validate(file.buffer, file.mimetype);
    const variants = await this.imageProcessing.generateVariants(file.buffer);

    const imageId = randomUUID();
    const basePath = `${product.establishment.organizationId}/${establishmentId}/${productId}/${imageId}`;

    // Upload sequentially: if one variant fails we can tell exactly which
    // ones already landed, rather than racing partial uploads.
    for (const [variant, buffer] of Object.entries(variants) as [ImageVariantName, Buffer][]) {
      await this.storage.upload(accessToken, `${basePath}-${variant}.webp`, buffer, 'image/webp');
    }

    const existingCount = await this.prisma.productImage.count({ where: { productId } });
    return this.prisma.productImage.create({
      data: {
        id: imageId,
        productId,
        storagePath: basePath,
        isPrimary: existingCount === 0,
        position: existingCount,
      },
    });
  }

  async remove(accessToken: string, establishmentId: string, productId: string, imageId: string): Promise<void> {
    await this.assertProductBelongsToEstablishment(establishmentId, productId);
    const image = await this.prisma.productImage.findFirst({ where: { id: imageId, productId } });
    if (!image) {
      throw new NotFoundException('Photo introuvable pour ce produit');
    }

    const paths = (Object.keys(IMAGE_VARIANT_SIZES) as ImageVariantName[]).map(
      (variant) => `${image.storagePath}-${variant}.webp`,
    );
    await this.storage.remove(accessToken, paths);
    await this.prisma.productImage.delete({ where: { id: imageId } });

    if (image.isPrimary) {
      const next = await this.prisma.productImage.findFirst({ where: { productId }, orderBy: { position: 'asc' } });
      if (next) {
        await this.prisma.productImage.update({ where: { id: next.id }, data: { isPrimary: true } });
      }
    }
  }

  async setPrimary(establishmentId: string, productId: string, imageId: string) {
    await this.assertProductBelongsToEstablishment(establishmentId, productId);
    const image = await this.prisma.productImage.findFirst({ where: { id: imageId, productId } });
    if (!image) {
      throw new NotFoundException('Photo introuvable pour ce produit');
    }
    await this.prisma.$transaction([
      this.prisma.productImage.updateMany({ where: { productId }, data: { isPrimary: false } }),
      this.prisma.productImage.update({ where: { id: imageId }, data: { isPrimary: true } }),
    ]);
  }

  async getVariantUrl(
    accessToken: string,
    establishmentId: string,
    productId: string,
    imageId: string,
    variant: ImageVariantName,
  ): Promise<string> {
    await this.assertProductBelongsToEstablishment(establishmentId, productId);
    const image = await this.prisma.productImage.findFirst({ where: { id: imageId, productId } });
    if (!image) {
      throw new NotFoundException('Photo introuvable pour ce produit');
    }
    if (!(variant in IMAGE_VARIANT_SIZES)) {
      throw new BadRequestException(`Variante inconnue : ${variant}`);
    }
    return this.storage.createSignedUrl(accessToken, `${image.storagePath}-${variant}.webp`);
  }
}
