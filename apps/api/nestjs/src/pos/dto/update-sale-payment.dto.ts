import { IsIn } from 'class-validator';

export class UpdateSalePaymentDto {
  /** Correction du mode de paiement d'une ligne déjà enregistrée — Espèces/Mobile Money uniquement (voir SalesController.updatePaymentMethod), le montant ne se corrige pas ici. */
  @IsIn(['cash', 'mobile_money'])
  method!: 'cash' | 'mobile_money';
}
