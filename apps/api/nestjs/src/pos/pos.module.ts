import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { ActivityNotifierModule } from '../notifications/activity-notifier.module.js';
import { SalesController } from './sales.controller.js';
import { SalesService } from './sales.service.js';

@Module({
  imports: [AuthModule, ActivityNotifierModule],
  controllers: [SalesController],
  providers: [SalesService],
  exports: [SalesService],
})
export class PosModule {}
