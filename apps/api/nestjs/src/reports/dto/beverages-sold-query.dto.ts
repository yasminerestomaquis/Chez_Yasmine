import { Matches } from 'class-validator';

export class BeveragesSoldQueryDto {
  /**
   * Un ou plusieurs jours choisis par l'utilisateur (YYYY-MM-DD), séparés
   * par des virgules — sélection multiple de dates (demande utilisateur du
   * 2026-09-25). Chaque jour couvre 00:00:00 à 23:59:59.999, heure serveur
   * (même convention que ReportsService.resolveRange).
   */
  @Matches(/^\d{4}-\d{2}-\d{2}(,\d{4}-\d{2}-\d{2})*$/, {
    message: 'dates doit être une liste de dates YYYY-MM-DD séparées par des virgules',
  })
  dates!: string;
}
