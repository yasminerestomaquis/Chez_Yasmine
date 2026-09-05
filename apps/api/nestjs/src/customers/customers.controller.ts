import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CreateCustomerDto, UpdateCustomerDto } from './dto/customer.dto.js';
import { CustomersService } from './customers.service.js';

@Controller('establishments/:establishmentId/customers')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('customers.manage')
export class CustomersController {
  constructor(private readonly customers: CustomersService) {}

  @Get()
  list(@Param('establishmentId') establishmentId: string) {
    return this.customers.list(establishmentId);
  }

  @Get(':customerId')
  get(@Param('establishmentId') establishmentId: string, @Param('customerId') customerId: string) {
    return this.customers.get(establishmentId, customerId);
  }

  @Post()
  create(@Param('establishmentId') establishmentId: string, @Body() dto: CreateCustomerDto) {
    return this.customers.create(establishmentId, dto);
  }

  @Patch(':customerId')
  update(
    @Param('establishmentId') establishmentId: string,
    @Param('customerId') customerId: string,
    @Body() dto: UpdateCustomerDto,
  ) {
    return this.customers.update(establishmentId, customerId, dto);
  }

  @Delete(':customerId')
  @HttpCode(HttpStatus.NO_CONTENT)
  remove(@Param('establishmentId') establishmentId: string, @Param('customerId') customerId: string) {
    return this.customers.remove(establishmentId, customerId);
  }
}
