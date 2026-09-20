import { IsDateString, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export class CreateLossDto {
  /** Client-generated UUID — same idempotent-replay pattern as sales/stock movements (Phase 9). */
  @IsOptional()
  @IsUUID()
  id?: string;

  @IsUUID()
  productId!: string;

  @IsNumber()
  @Min(0.01)
  quantity!: number;

  @IsOptional()
  @IsString()
  reason?: string;

  /**
   * Date de la perte (ISO 8601) — antidatage réservé aux porteurs de
   * `losses.edit` (Super Administrateur/Gérant/Serveur, contrôlé par
   * `LossesController`/`SyncService`) ; sinon horodatage serveur.
   */
  @IsOptional()
  @IsDateString()
  createdAt?: string;
}
