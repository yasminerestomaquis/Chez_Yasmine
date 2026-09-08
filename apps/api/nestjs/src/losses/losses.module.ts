import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { ActivityNotifierModule } from '../notifications/activity-notifier.module.js';
import { LossesController } from './losses.controller.js';
import { LossesService } from './losses.service.js';

@Module({
  imports: [AuthModule, ActivityNotifierModule],
  controllers: [LossesController],
  providers: [LossesService],
})
export class LossesModule {}
