import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { StockController } from './stock.controller.js';
import { StockMovementsService } from './stock-movements.service.js';

@Module({
  imports: [AuthModule],
  controllers: [StockController],
  providers: [StockMovementsService],
})
export class StockModule {}
