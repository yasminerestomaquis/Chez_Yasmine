import { IsIn, IsInt, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';
import type { ManualStockMovementType } from '../stock-math.js';

export class CreateStockMovementDto {
  /** Client-generated UUID — lets an offline movement be replayed safely (see Phase 9 / docs/api/sync.md). */
  @IsOptional()
  @IsUUID()
  id?: string;

  /** 'loss' is deliberately not accepted here since Phase 12 — see src/losses/ — so that every stock loss carries a Loss accounting record, not just a StockMovement. */
  @IsIn(['in', 'out', 'adjustment'])
  type!: ManualStockMovementType;

  @IsNumber()
  @Min(0)
  quantity!: number;

  @IsOptional()
  @IsString()
  reason?: string;

  /**
   * N° de marché (dépense "Marché" déjà enregistrée) — requis par
   * `StockMovementsService.create` pour toute entrée ('in') sur un produit
   * d'une catégorie à prix variable (Poulets, Poissons, Plats africains),
   * pour que le lot FIFO créé soit rattachable à ce marché (voir
   * docs/api/charts.md, principe de numérotation des lots). Ignoré pour les
   * autres catégories/types de mouvement.
   */
  @IsOptional()
  @IsInt()
  @Min(1)
  marketNumber?: number;
}
