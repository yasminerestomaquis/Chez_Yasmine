import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { CashController } from './cash.controller.js';
import { CashService } from './cash.service.js';

@Module({
  imports: [AuthModule],
  controllers: [CashController],
  providers: [CashService],
})
export class CashModule {}
