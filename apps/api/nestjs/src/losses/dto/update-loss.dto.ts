import { IsDateString, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';

/** Correction d'une perte déjà enregistrée : date, produit, quantité, motif — tous optionnels, seuls les champs fournis changent. */
export class UpdateLossDto {
  @IsOptional()
  @IsUUID()
  productId?: string;

  @IsOptional()
  @IsNumber()
  @Min(0.01)
  quantity?: number;

  @IsOptional()
  @IsString()
  reason?: string;

  /** Date de la perte (ISO 8601). */
  @IsOptional()
  @IsDateString()
  createdAt?: string;
}
