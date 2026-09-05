import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { OrdersController } from './orders.controller.js';
import { OrdersService } from './orders.service.js';
import { TablesController } from './tables.controller.js';
import { TablesService } from './tables.service.js';

@Module({
  imports: [AuthModule],
  controllers: [TablesController, OrdersController],
  providers: [TablesService, OrdersService],
})
export class TablesModule {}
