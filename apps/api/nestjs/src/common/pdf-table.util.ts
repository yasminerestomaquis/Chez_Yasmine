import PDFDocument from 'pdfkit';

/** "147000" → "147 000" — même convention que `formatAmount` côté Flutter (lib/common/formatting.dart). */
export function formatFcfa(value: number): string {
  const rounded = Math.round(value);
  const digits = Math.abs(rounded).toString();
  let out = '';
  for (let i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 === 0) out += ' ';
    out += digits[i];
  }
  return rounded < 0 ? `-${out}` : out;
}

export interface PdfTableColumn {
  header: string;
  width: number;
  align?: 'left' | 'right' | 'center';
}

/**
 * Réduit proportionnellement des largeurs de colonnes pour qu'elles tiennent
 * dans `availableWidth`, sans jamais les agrandir — un tableau déjà étroit
 * garde ses largeurs telles quelles. Sans ça, les dernières colonnes d'un
 * tableau trop large se dessinent hors de la page et ne sont jamais visibles
 * à l'impression/l'export (bug constaté le 2026-09-27 sur "Stock actif", 14
 * colonnes). Extrait de `drawPdfTable` pour être testable isolément.
 */
export function scaleColumnWidths(widths: number[], availableWidth: number): number[] {
  const total = widths.reduce((sum, w) => sum + w, 0);
  if (total <= availableWidth || total <= 0) return widths;
  const scale = availableWidth / total;
  return widths.map((w) => w * scale);
}

/**
 * Dessine un tableau avec quadrillage complet — bordures verticales ET
 * horizontales sur chaque cellule, y compris la ligne d'en-tête et une
 * éventuelle ligne de total — décision utilisateur du 2026-09-25 : les
 * exports du module Rapports passent d'Excel à PDF, mais doivent rester
 * lisibles comme un tableau, pas un simple bloc de texte. L'en-tête se
 * reconduit sur chaque nouvelle page (décision utilisateur du 2026-09-27) et
 * les colonnes sont automatiquement réduites (`scaleColumnWidths`) si leur
 * somme dépasse la largeur imprimable de la page.
 *
 * pdfkit n'a pas de primitive "tableau" native (jusqu'à la version utilisée
 * ici) : chaque cellule est un rectangle dessiné explicitement plutôt que de
 * dépendre d'une méthode `.table()` dont le comportement de bordures varie
 * selon la version — ça garantit un quadrillage complet, prévisible, quelle
 * que soit la mise à jour future de la librairie.
 */
export function drawPdfTable(
  doc: PDFKit.PDFDocument,
  columns: PdfTableColumn[],
  rows: string[][],
  options: { startX?: number; rowHeight?: number; boldRowIndexes?: Set<number> } = {},
): void {
  const startX = options.startX ?? doc.page.margins.left;
  const rowHeight = options.rowHeight ?? 22;
  const boldRowIndexes = options.boldRowIndexes ?? new Set<number>();
  const availableWidth = doc.page.width - doc.page.margins.left - doc.page.margins.right;
  const widths = scaleColumnWidths(
    columns.map((c) => c.width),
    availableWidth,
  );
  const headerCells = columns.map((c) => c.header);

  // Hauteur de la ligne d'en-tête mesurée sur son propre texte, jamais
  // `rowHeight` (celle, fixe, des lignes de données) : avec des colonnes
  // resserrées et des libellés longs, un en-tête tenu à la même hauteur
  // qu'une ligne de donnée se faisait chevaucher par la ligne suivante (bug
  // constaté le 2026-09-27, "Stock actif", 14 colonnes) — décision
  // utilisateur du même jour.
  doc.font('Helvetica-Bold').fontSize(9);
  const headerHeight = Math.max(
    rowHeight,
    ...headerCells.map((text, i) => doc.heightOfString(text, { width: widths[i] - 8 }) + 12),
  );

  const drawCells = (cells: string[], bold: boolean, height: number) => {
    const y = doc.y;
    let x = startX;
    doc.font(bold ? 'Helvetica-Bold' : 'Helvetica').fontSize(9);
    for (let i = 0; i < columns.length; i++) {
      doc.rect(x, y, widths[i], height).stroke();
      doc.text(cells[i] ?? '', x + 4, y + 6, { width: widths[i] - 8, align: columns[i].align ?? 'left' });
      x += widths[i];
    }
    doc.y = y + height;
  };

  const drawHeader = () => drawCells(headerCells, true, headerHeight);

  const drawRow = (cells: string[], bold: boolean) => {
    const pageBottom = doc.page.height - doc.page.margins.bottom;
    if (doc.y + rowHeight > pageBottom) {
      doc.addPage();
      drawHeader();
    }
    drawCells(cells, bold, rowHeight);
  };

  drawHeader();
  rows.forEach((row, i) => drawRow(row, boldRowIndexes.has(i)));
}
