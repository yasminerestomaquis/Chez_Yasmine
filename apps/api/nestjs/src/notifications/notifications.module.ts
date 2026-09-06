import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { StockModule } from '../stock/stock.module.js';
import { NotificationsController } from './notifications.controller.js';
import { NotificationsService } from './notifications.service.js';

@Module({
  imports: [AuthModule, StockModule],
  controllers: [NotificationsController],
  providers: [NotificationsService],
})
export class NotificationsModule {}
