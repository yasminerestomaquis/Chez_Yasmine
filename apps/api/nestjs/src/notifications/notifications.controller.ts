import { Body, Controller, Get, HttpCode, HttpStatus, Param, Patch, Post, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { BroadcastNotificationDto } from './dto/notification.dto.js';
import { NotificationsService } from './notifications.service.js';

@Controller('establishments/:establishmentId/notifications')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
export class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  // No @RequirePermissions below: any establishment member may read their
  // own notifications (NotificationsService.getOrganizationId is what
  // actually enforces membership) — same pattern as GET /auth/me.

  @Get()
  list(@Req() request: Request, @Param('establishmentId') establishmentId: string) {
    return this.notifications.list(establishmentId, request.user!.sub);
  }

  @Get('unread-count')
  unreadCount(@Req() request: Request, @Param('establishmentId') establishmentId: string) {
    return this.notifications.unreadCount(establishmentId, request.user!.sub);
  }

  @Patch(':notificationId/read')
  @HttpCode(HttpStatus.NO_CONTENT)
  markAsRead(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Param('notificationId') notificationId: string,
  ) {
    return this.notifications.markAsRead(establishmentId, request.user!.sub, notificationId);
  }

  @Post('broadcast')
  @RequirePermissions('settings.manage')
  broadcast(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Body() dto: BroadcastNotificationDto,
  ) {
    return this.notifications.broadcast(establishmentId, request.user!.sub, dto);
  }

  @Post('low-stock-check')
  @RequirePermissions('stock.manage')
  generateLowStockAlerts(@Req() request: Request, @Param('establishmentId') establishmentId: string) {
    return this.notifications.generateLowStockAlerts(establishmentId, request.user!.sub);
  }
}
