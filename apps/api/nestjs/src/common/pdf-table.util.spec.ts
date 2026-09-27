import PDFDocument from 'pdfkit';
import { PDFParse } from 'pdf-parse';
import { describe, expect, it } from 'vitest';
import { drawPdfTable, scaleColumnWidths } from './pdf-table.util.js';

describe('scaleColumnWidths', () => {
  it('leaves widths untouched when they already fit', () => {
    expect(scaleColumnWidths([100, 200, 300], 800)).toEqual([100, 200, 300]);
  });

  it('shrinks every width proportionally, never enlarging, when the total exceeds the available width', () => {
    // Total 1000, disponible 500 -> facteur 0,5.
    expect(scaleColumnWidths([200, 300, 500], 500)).toEqual([100, 150, 250]);
  });

  it('leaves widths untouched for an empty or zero-width input', () => {
    expect(scaleColumnWidths([], 500)).toEqual([]);
  });
});

async function pdfText(doc: PDFKit.PDFDocument): Promise<string> {
  const chunks: Buffer[] = [];
  doc.on('data', (chunk: Buffer) => chunks.push(chunk));
  const done = new Promise<void>((resolve) => doc.on('end', () => resolve()));
  doc.end();
  await done;
  const buffer = Buffer.concat(chunks);
  const parser = new PDFParse({ data: buffer });
  const result = await parser.getText();
  await parser.destroy();
  return result.text;
}

describe('drawPdfTable', () => {
  it('shrinks columns wider than the printable page area so every column stays visible (2026-09-27)', async () => {
    // Page A4 portrait (595pt de large, marges 30 -> ~535pt imprimables) avec
    // des colonnes totalisant bien plus que ça : sans la mise à l'échelle,
    // les dernières ne seraient jamais dessinées à l'intérieur de la page.
    const doc = new PDFDocument({ margin: 30, size: 'A4' });
    drawPdfTable(
      doc,
      [
        { header: 'Colonne A', width: 200 },
        { header: 'Colonne B', width: 200 },
        { header: 'Colonne C', width: 200 },
        { header: 'DerniereColonne', width: 200 },
      ],
      [['a', 'b', 'c', 'd']],
    );
    const text = await pdfText(doc);

    expect(text).toContain('DerniereColonne');
  });

  it("repeats the header row on every new page (décision utilisateur du 2026-09-27)", async () => {
    const doc = new PDFDocument({ margin: 30, size: 'A4' });
    // Assez de lignes pour forcer un saut de page (rowHeight 22pt, page A4
    // portrait ~ 35 lignes par page).
    const rows = Array.from({ length: 60 }, (_, i) => [`Produit ${i}`]);
    drawPdfTable(doc, [{ header: 'EnTeteUnique', width: 200 }], rows);
    const text = await pdfText(doc);

    const occurrences = text.match(/EnTeteUnique/g)?.length ?? 0;
    expect(occurrences).toBeGreaterThanOrEqual(2);
  });

  it('gives the header row extra height when its text needs several lines, instead of the fixed data row height (2026-09-27)', () => {
    const doc = new PDFDocument({ margin: 30, size: 'A4' });
    const before = doc.y;
    drawPdfTable(
      doc,
      [{ header: 'Un intitulé de colonne bien trop long pour tenir sur une seule ligne dans une colonne aussi étroite', width: 60 }],
      [['x']],
    );
    // Une ligne de donnée fait toujours 22pt (hauteur fixe) ; si l'en-tête en
    // avait fait autant malgré un texte qui a besoin de plusieurs lignes, le
    // total après en-tête + 1 ligne ne dépasserait pas 44pt.
    expect(doc.y - before).toBeGreaterThan(22 + 22);
  });
});
