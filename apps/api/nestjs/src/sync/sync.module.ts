import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { PosModule } from '../pos/pos.module.js';
import { StockModule } from '../stock/stock.module.js';
import { SyncController } from './sync.controller.js';
import { SyncService } from './sync.service.js';

@Module({
  imports: [AuthModule, PosModule, StockModule],
  controllers: [SyncController],
  providers: [SyncService],
})
export class SyncModule {}
