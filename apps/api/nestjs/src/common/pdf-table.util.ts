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
 * Dessine un tableau avec quadrillage complet — bordures verticales ET
 * horizontales sur chaque cellule, y compris la ligne d'en-tête et une
 * éventuelle ligne de total — décision utilisateur du 2026-09-25 : les
 * exports du module Rapports passent d'Excel à PDF, mais doivent rester
 * lisibles comme un tableau, pas un simple bloc de texte.
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
  const pageBottom = doc.page.height - doc.page.margins.bottom;

  const drawRow = (cells: string[], bold: boolean) => {
    if (doc.y + rowHeight > pageBottom) {
      doc.addPage();
    }
    const y = doc.y;
    let x = startX;
    doc.font(bold ? 'Helvetica-Bold' : 'Helvetica').fontSize(9);
    for (let i = 0; i < columns.length; i++) {
      const col = columns[i];
      doc.rect(x, y, col.width, rowHeight).stroke();
      doc.text(cells[i] ?? '', x + 4, y + 6, { width: col.width - 8, align: col.align ?? 'left' });
      x += col.width;
    }
    doc.y = y + rowHeight;
  };

  drawRow(columns.map((c) => c.header), true);
  rows.forEach((row, i) => drawRow(row, boldRowIndexes.has(i)));
}
