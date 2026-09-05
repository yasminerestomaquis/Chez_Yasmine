import { Module } from '@nestjs/common';
import { ImageProcessingService } from './image-processing.service.js';
import { SupabaseStorageService } from './supabase-storage.service.js';

@Module({
  providers: [ImageProcessingService, SupabaseStorageService],
  exports: [ImageProcessingService, SupabaseStorageService],
})
export class StorageModule {}
