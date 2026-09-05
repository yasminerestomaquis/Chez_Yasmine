import { Module } from '@nestjs/common';
import { AppController } from './app.controller.js';
import { AppService } from './app.service.js';
import { AuthModule } from './auth/auth.module.js';
import { CashModule } from './cash/cash.module.js';
import { CatalogModule } from './catalog/catalog.module.js';
import { CustomersModule } from './customers/customers.module.js';
import { ExpensesModule } from './expenses/expenses.module.js';
import { LossesModule } from './losses/losses.module.js';
import { PosModule } from './pos/pos.module.js';
import { PrismaModule } from './prisma/prisma.module.js';
import { PurchasingModule } from './purchasing/purchasing.module.js';
import { StockModule } from './stock/stock.module.js';
import { SyncModule } from './sync/sync.module.js';
import { TablesModule } from './tables/tables.module.js';

@Module({
  imports: [
    PrismaModule,
    AuthModule,
    CatalogModule,
    StockModule,
    PosModule,
    TablesModule,
    SyncModule,
    PurchasingModule,
    CustomersModule,
    ExpensesModule,
    LossesModule,
    CashModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
