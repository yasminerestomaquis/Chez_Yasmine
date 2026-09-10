import { Body, Controller, Delete, Get, Param, Post, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { AddOrderItemDto, MergeOrderDto, OpenTableDto, SplitOrderDto, TransferOrderDto } from './dto/order-operations.dto.js';
import { OrdersService } from './orders.service.js';

@Controller('establishments/:establishmentId')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('tables.manage')
export class OrdersController {
  constructor(private readonly orders: OrdersService) {}

  @Post('tables/:tableId/open')
  openTable(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Param('tableId') tableId: string,
    @Body() dto: OpenTableDto,
  ) {
    return this.orders.openTable(establishmentId, tableId, request.user!.sub, dto.guestCount);
  }

  @Get('tables/:tableId/orders')
  listOpenOrdersForTable(@Param('establishmentId') establishmentId: string, @Param('tableId') tableId: string) {
    return this.orders.listOpenOrdersForTable(establishmentId, tableId);
  }

  @Post('orders/:orderId/items')
  addItem(
    @Param('establishmentId') establishmentId: string,
    @Param('orderId') orderId: string,
    @Body() dto: AddOrderItemDto,
  ) {
    return this.orders.addItem(establishmentId, orderId, dto);
  }

  @Delete('orders/:orderId/items/:itemId')
  removeItem(
    @Param('establishmentId') establishmentId: string,
    @Param('orderId') orderId: string,
    @Param('itemId') itemId: string,
  ) {
    return this.orders.removeItem(establishmentId, orderId, itemId);
  }

  @Post('orders/:orderId/transfer')
  transfer(
    @Param('establishmentId') establishmentId: string,
    @Param('orderId') orderId: string,
    @Body() dto: TransferOrderDto,
  ) {
    return this.orders.transfer(establishmentId, orderId, dto);
  }

  @Post('orders/:orderId/merge')
  merge(@Param('establishmentId') establishmentId: string, @Param('orderId') orderId: string, @Body() dto: MergeOrderDto) {
    return this.orders.merge(establishmentId, orderId, dto.intoOrderId);
  }

  @Post('orders/:orderId/split')
  split(@Param('establishmentId') establishmentId: string, @Param('orderId') orderId: string, @Body() dto: SplitOrderDto) {
    return this.orders.split(establishmentId, orderId, dto);
  }
}
