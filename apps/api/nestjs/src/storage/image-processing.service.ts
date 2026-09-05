import { BadRequestException, Injectable } from '@nestjs/common';
import sharp from 'sharp';

const ALLOWED_MIME_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/gif']);
const MAX_UPLOAD_BYTES = 8 * 1024 * 1024; // 8 MB

/** width, in pixels, of the longest side for each variant — see prompt maître §21. */
export const IMAGE_VARIANT_SIZES = {
  thumbnail: 150,
  small: 400,
  medium: 800,
  large: 1600,
} as const;

export type ImageVariantName = keyof typeof IMAGE_VARIANT_SIZES;

@Injectable()
export class ImageProcessingService {
  /** Validates MIME type, size, and that the bytes actually decode as an image (never trust the client-declared MIME type alone). */
  async validate(buffer: Buffer, declaredMimeType: string): Promise<void> {
    if (!ALLOWED_MIME_TYPES.has(declaredMimeType)) {
      throw new BadRequestException(`Type de fichier non autorisé : ${declaredMimeType}`);
    }
    if (buffer.length === 0 || buffer.length > MAX_UPLOAD_BYTES) {
      throw new BadRequestException(`Fichier invalide ou trop volumineux (max ${MAX_UPLOAD_BYTES / (1024 * 1024)} Mo)`);
    }
    try {
      const metadata = await sharp(buffer).metadata();
      if (!metadata.width || !metadata.height) {
        throw new Error('no dimensions');
      }
    } catch {
      throw new BadRequestException("Le fichier fourni n'est pas une image valide");
    }
  }

  /** Produces WebP variants at each size in IMAGE_VARIANT_SIZES, never upscaling past the source. */
  async generateVariants(buffer: Buffer): Promise<Record<ImageVariantName, Buffer>> {
    const entries = await Promise.all(
      (Object.entries(IMAGE_VARIANT_SIZES) as [ImageVariantName, number][]).map(async ([name, width]) => {
        const output = await sharp(buffer)
          .rotate() // apply EXIF orientation before resizing
          .resize({ width, withoutEnlargement: true })
          .webp({ quality: 80 })
          .toBuffer();
        return [name, output] as const;
      }),
    );
    return Object.fromEntries(entries) as Record<ImageVariantName, Buffer>;
  }
}
