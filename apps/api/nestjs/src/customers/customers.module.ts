import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { CreditsController } from './credits.controller.js';
import { CreditsService } from './credits.service.js';
import { CustomersController } from './customers.controller.js';
import { CustomersService } from './customers.service.js';

@Module({
  imports: [AuthModule],
  controllers: [CustomersController, CreditsController],
  providers: [CustomersService, CreditsService],
})
export class CustomersModule {}
