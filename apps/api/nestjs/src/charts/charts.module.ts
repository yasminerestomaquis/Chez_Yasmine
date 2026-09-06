import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { ChartsController } from './charts.controller.js';
import { ChartsService } from './charts.service.js';

@Module({
  imports: [AuthModule],
  controllers: [ChartsController],
  providers: [ChartsService],
})
export class ChartsModule {}
