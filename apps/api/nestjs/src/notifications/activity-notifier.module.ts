import { Module } from '@nestjs/common';
import { ActivityNotifierService } from './activity-notifier.service.js';

/** Voir activity-notifier.service.ts pour pourquoi ce module est séparé de NotificationsModule. */
@Module({
  providers: [ActivityNotifierService],
  exports: [ActivityNotifierService],
})
export class ActivityNotifierModule {}
