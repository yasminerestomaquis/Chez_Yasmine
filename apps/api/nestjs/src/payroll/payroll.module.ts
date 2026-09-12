import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { ActivityNotifierModule } from '../notifications/activity-notifier.module.js';
import { EmployeesController } from './employees.controller.js';
import { EmployeesService } from './employees.service.js';
import { PayrollController } from './payroll.controller.js';
import { PayrollService } from './payroll.service.js';

@Module({
  imports: [AuthModule, ActivityNotifierModule],
  controllers: [EmployeesController, PayrollController],
  providers: [EmployeesService, PayrollService],
})
export class PayrollModule {}
