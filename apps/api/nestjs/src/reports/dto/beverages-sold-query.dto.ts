import { IsDateString } from 'class-validator';

export class BeveragesSoldQueryDto {
  /** Jour choisi par l'utilisateur (YYYY-MM-DD) — le listing couvre 00:00:00 à 23:59:59.999 ce jour-là, heure serveur (même convention que ReportsService.resolveRange). */
  @IsDateString()
  date!: string;
}
