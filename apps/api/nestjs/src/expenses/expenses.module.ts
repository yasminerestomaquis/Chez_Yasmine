import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { ActivityNotifierModule } from '../notifications/activity-notifier.module.js';
import { ExpensesController } from './expenses.controller.js';
import { ExpensesService } from './expenses.service.js';

@Module({
  imports: [AuthModule, ActivityNotifierModule],
  controllers: [ExpensesController],
  providers: [ExpensesService],
  exports: [ExpensesService],
})
export class ExpensesModule {}
