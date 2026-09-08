import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { ActivityNotifierModule } from '../notifications/activity-notifier.module.js';
import { StockController } from './stock.controller.js';
import { StockMovementsService } from './stock-movements.service.js';

@Module({
  imports: [AuthModule, ActivityNotifierModule],
  controllers: [StockController],
  providers: [StockMovementsService],
  exports: [StockMovementsService],
})
export class StockModule {}
