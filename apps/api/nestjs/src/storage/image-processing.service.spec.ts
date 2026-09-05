import { BadRequestException } from '@nestjs/common';
import sharp from 'sharp';
import { beforeAll, describe, expect, it } from 'vitest';
import { IMAGE_VARIANT_SIZES, ImageProcessingService } from './image-processing.service.js';

describe('ImageProcessingService', () => {
  const service = new ImageProcessingService();
  let validJpeg: Buffer;

  beforeAll(async () => {
    // A real, decodable 2000x1000 JPEG — large enough that every variant
    // actually gets resized down (not just passed through).
    validJpeg = await sharp({
      create: { width: 2000, height: 1000, channels: 3, background: { r: 220, g: 120, b: 40 } },
    })
      .jpeg()
      .toBuffer();
  });

  describe('validate', () => {
    it('accepts a real JPEG under the size limit', async () => {
      await expect(service.validate(validJpeg, 'image/jpeg')).resolves.toBeUndefined();
    });

    it('rejects a disallowed MIME type', async () => {
      await expect(service.validate(validJpeg, 'application/pdf')).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects an empty buffer', async () => {
      await expect(service.validate(Buffer.alloc(0), 'image/jpeg')).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects bytes that are not actually a decodable image, even with an image/* MIME type', async () => {
      const notAnImage = Buffer.from('this is definitely not an image');
      await expect(service.validate(notAnImage, 'image/png')).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects a file larger than the size limit', async () => {
      const oversized = Buffer.concat([validJpeg, Buffer.alloc(9 * 1024 * 1024)]);
      await expect(service.validate(oversized, 'image/jpeg')).rejects.toBeInstanceOf(BadRequestException);
    });
  });

  describe('generateVariants', () => {
    it('produces one WebP buffer per configured size, each resized down and none upscaled', async () => {
      const variants = await service.generateVariants(validJpeg);

      for (const [name, maxWidth] of Object.entries(IMAGE_VARIANT_SIZES)) {
        const buffer = variants[name as keyof typeof variants];
        expect(buffer.length).toBeGreaterThan(0);
        const metadata = await sharp(buffer).metadata();
        expect(metadata.format).toBe('webp');
        expect(metadata.width).toBeLessThanOrEqual(maxWidth);
        expect(metadata.width).toBeLessThanOrEqual(2000);
      }
    });

    it('never enlarges a source smaller than a variant size', async () => {
      const tinySource = await sharp({
        create: { width: 40, height: 40, channels: 3, background: { r: 10, g: 10, b: 10 } },
      })
        .png()
        .toBuffer();

      const variants = await service.generateVariants(tinySource);
      const large = await sharp(variants.large).metadata();
      expect(large.width).toBeLessThanOrEqual(40);
    });
  });
});
