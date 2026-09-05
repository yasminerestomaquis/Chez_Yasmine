import { Module } from '@nestjs/common';
import { AppController } from './app.controller.js';
import { AppService } from './app.service.js';
import { AuthModule } from './auth/auth.module.js';
import { CatalogModule } from './catalog/catalog.module.js';
import { PosModule } from './pos/pos.module.js';
import { PrismaModule } from './prisma/prisma.module.js';
import { StockModule } from './stock/stock.module.js';
import { TablesModule } from './tables/tables.module.js';

@Module({
  imports: [PrismaModule, AuthModule, CatalogModule, StockModule, PosModule, TablesModule],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
