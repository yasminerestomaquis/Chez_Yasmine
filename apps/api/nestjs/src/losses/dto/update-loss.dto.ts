import { IsBoolean, IsDateString, IsInt, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';

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

  /** Valoriser au prix à l'unité plutôt qu'au tarif du lot — ignoré si le produit n'a pas de prix à l'unité. */
  @IsOptional()
  @IsBoolean()
  sellAsUnit?: boolean;

  /** N° de la commande (Achats) — obligatoire pour un produit à prix par casier. */
  @IsOptional()
  @IsInt()
  @Min(1)
  orderNumber?: number;
}
