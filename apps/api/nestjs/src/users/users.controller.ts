import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Patch, Post, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { InviteUserDto } from './dto/invite-user.dto.js';
import { UpdateMemberDto } from './dto/update-member.dto.js';
import { UsersService } from './users.service.js';

@Controller('establishments/:establishmentId')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
@RequirePermissions('users.manage')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get('users')
  list(@Param('establishmentId') establishmentId: string) {
    return this.users.list(establishmentId);
  }

  @Get('roles')
  listRoles(@Param('establishmentId') establishmentId: string) {
    return this.users.listAvailableRoles(establishmentId);
  }

  @Post('users/invite')
  invite(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Body() dto: InviteUserDto) {
    return this.users.invite(establishmentId, request.user!.sub, dto);
  }

  @Post('users/invite-link')
  generateInviteLink(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Body() dto: InviteUserDto,
  ) {
    return this.users.generateInviteLink(establishmentId, request.user!.sub, dto);
  }

  @Patch('users/:membershipId')
  updateMember(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Param('membershipId') membershipId: string,
    @Body() dto: UpdateMemberDto,
  ) {
    return this.users.updateMember(establishmentId, request.user!.sub, membershipId, dto);
  }

  @Post('users/:membershipId/recovery-link')
  generateRecoveryLink(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Param('membershipId') membershipId: string,
  ) {
    return this.users.generateRecoveryLink(establishmentId, request.user!.sub, membershipId);
  }

  @Delete('users/:membershipId')
  @HttpCode(HttpStatus.NO_CONTENT)
  removeMember(
    @Req() request: Request,
    @Param('establishmentId') establishmentId: string,
    @Param('membershipId') membershipId: string,
  ) {
    return this.users.removeMember(establishmentId, request.user!.sub, membershipId);
  }
}
