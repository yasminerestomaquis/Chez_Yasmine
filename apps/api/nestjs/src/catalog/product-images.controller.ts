import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  Patch,
  Post,
  Query,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import type { Request } from 'express';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import type { ImageVariantName } from '../storage/image-processing.service.js';
import { IMAGE_VARIANT_SIZES } from '../storage/image-processing.service.js';
import { ProductImagesService } from './product-images.service.js';

@Controller('establishments/:establishmentId/products/:productId/images')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('products.manage')
export class ProductImagesController {
  constructor(private readonly images: ProductImagesService) {}

  @Post()
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: 8 * 1024 * 1024 } }))
  upload(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Param('productId') productId: string,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    if (!file) {
      throw new BadRequestException("Aucun fichier reçu (champ attendu : 'file')");
    }
    return this.images.upload(request.supabaseAccessToken!, establishmentId, productId, file);
  }

  @Delete(':imageId')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Param('productId') productId: string,
    @Param('imageId') imageId: string,
  ) {
    return this.images.remove(request.supabaseAccessToken!, establishmentId, productId, imageId);
  }

  @Patch(':imageId')
  setPrimary(
    @Param('establishmentId') establishmentId: string,
    @Param('productId') productId: string,
    @Param('imageId') imageId: string,
    @Body('isPrimary') isPrimary: boolean,
  ) {
    if (isPrimary !== true) {
      throw new BadRequestException("Seul { isPrimary: true } est supporté pour l'instant");
    }
    return this.images.setPrimary(establishmentId, productId, imageId);
  }

  // Lecture (`products.view`) séparée de la gestion (`products.manage`,
  // niveau contrôleur ci-dessus) : la grille produits de la Caisse affiche
  // les photos pour tout rôle qui vend (`pos.sell`), pas seulement ceux qui
  // gèrent le catalogue — même raison que ProductsController.list.
  @Get(':imageId/url')
  @RequirePermissions('products.view')
  getVariantUrl(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Param('productId') productId: string,
    @Param('imageId') imageId: string,
    @Query('variant') variant: string = 'medium',
  ) {
    if (!(variant in IMAGE_VARIANT_SIZES)) {
      throw new BadRequestException(`Variante inconnue : ${variant}`);
    }
    return this.images
      .getVariantUrl(request.supabaseAccessToken!, establishmentId, productId, imageId, variant as ImageVariantName)
      .then((url) => ({ url }));
  }
}
