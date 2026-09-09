import { Module } from '@nestjs/common';
import { AppController } from './app.controller.js';
import { AppService } from './app.service.js';
import { AuthModule } from './auth/auth.module.js';
import { CashModule } from './cash/cash.module.js';
import { CatalogModule } from './catalog/catalog.module.js';
import { ChartsModule } from './charts/charts.module.js';
import { CustomersModule } from './customers/customers.module.js';
import { ExpensesModule } from './expenses/expenses.module.js';
import { LossesModule } from './losses/losses.module.js';
import { NotificationsModule } from './notifications/notifications.module.js';
import { PosModule } from './pos/pos.module.js';
import { PrismaModule } from './prisma/prisma.module.js';
import { PurchasingModule } from './purchasing/purchasing.module.js';
import { ReportsModule } from './reports/reports.module.js';
import { StockModule } from './stock/stock.module.js';
import { SyncModule } from './sync/sync.module.js';
import { TablesModule } from './tables/tables.module.js';
import { UsersModule } from './users/users.module.js';

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
    ReportsModule,
    NotificationsModule,
    ChartsModule,
    UsersModule,
  ],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
