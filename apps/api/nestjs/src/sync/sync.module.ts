import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { CashModule } from '../cash/cash.module.js';
import { ExpensesModule } from '../expenses/expenses.module.js';
import { LossesModule } from '../losses/losses.module.js';
import { PosModule } from '../pos/pos.module.js';
import { PurchasingModule } from '../purchasing/purchasing.module.js';
import { StockModule } from '../stock/stock.module.js';
import { SyncController } from './sync.controller.js';
import { SyncService } from './sync.service.js';

@Module({
  imports: [AuthModule, PosModule, StockModule, ExpensesModule, LossesModule, PurchasingModule, CashModule],
  controllers: [SyncController],
  providers: [SyncService],
})
export class SyncModule {}
