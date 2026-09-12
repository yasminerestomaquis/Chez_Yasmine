import { Body, Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CreateEmployeeDto, UpdateEmployeeDto } from './dto/employee.dto.js';
import { EmployeesService } from './employees.service.js';

@Controller('establishments/:establishmentId/employees')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
export class EmployeesController {
  constructor(private readonly employees: EmployeesService) {}

  @Get()
  @RequirePermissions('payroll.view')
  list(@Param('establishmentId') establishmentId: string) {
    return this.employees.list(establishmentId);
  }

  @Post()
  @RequirePermissions('payroll.manage')
  create(@Param('establishmentId') establishmentId: string, @Body() dto: CreateEmployeeDto) {
    return this.employees.create(establishmentId, dto);
  }

  @Patch(':employeeId')
  @RequirePermissions('payroll.manage')
  update(
    @Param('establishmentId') establishmentId: string,
    @Param('employeeId') employeeId: string,
    @Body() dto: UpdateEmployeeDto,
  ) {
    return this.employees.update(establishmentId, employeeId, dto);
  }
}
