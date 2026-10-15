import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { ActivityNotifierModule } from '../notifications/activity-notifier.module.js';
import { SalesController } from './sales.controller.js';
import { SalesService } from './sales.service.js';
import { SellGroupsService } from './sell-groups.service.js';

@Module({
  imports: [AuthModule, ActivityNotifierModule],
  controllers: [SalesController],
  providers: [SalesService, SellGroupsService],
  exports: [SalesService, SellGroupsService],
})
export class PosModule {}
