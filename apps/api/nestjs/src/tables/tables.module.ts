import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { PosModule } from '../pos/pos.module.js';
import { OrdersController } from './orders.controller.js';
import { OrdersService } from './orders.service.js';
import { ReservationsController } from './reservations.controller.js';
import { ReservationsService } from './reservations.service.js';
import { TablesController } from './tables.controller.js';
import { TablesService } from './tables.service.js';

@Module({
  imports: [AuthModule, PosModule],
  controllers: [TablesController, OrdersController, ReservationsController],
  providers: [TablesService, OrdersService, ReservationsService],
  exports: [OrdersService],
})
export class TablesModule {}
