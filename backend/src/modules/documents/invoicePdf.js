import PDFDocument from "pdfkit";

import {
  PAGE_MARGIN,
  FOOTER_SPACE,
  INK,
  INK_SOFT,
  PAPER_SOFT,
  RULE,
  ON_DARK,
  attachFooter,
  drawBand,
  drawMetaStrip,
  drawNotePanel,
  formatDate,
  geometry,
  humanise,
  money,
} from "./documentChrome.js";

/**
 * §28's PDF, generated server-side.
 *
 * The client already renders an on-screen preview; this produces the file that
 * gets printed, emailed or filed, and it does so from the DOCUMENT rather than
 * from whatever the screen happens to be showing. That matters for §55: the PDF
 * of an order placed last year must show the names and prices as they were, and
 * the only place those survive is the order's own lines.
 *
 * Streamed rather than buffered: an invoice is small, but the same function will
 * serve a statement of a hundred lines, and holding the whole file in memory to
 * measure it before sending it buys nothing.
 *
 * NO NUMBERS ARE COMPUTED HERE. Every figure is taken from the document as
 * stored — a PDF that adds its lines up its own way is how a customer ends up
 * holding a piece of paper the system disagrees with.
 *
 * NOTHING IN IT IS NON-DETERMINISTIC either: no "generated at", no run id. Two
 * renders of the same order are byte-identical, which is what makes a reprint
 * trustworthy and is asserted in `documents.customfields.backups.test.js`.
 *
 * ─────────────────────────────────────────────────────────────────────────
 * THE LAYOUT, AND WHY IT IS BLOCKS RATHER THAN A COLUMN OF TEXT
 *
 * It used to be one flow: title, address lines, a thin table, totals. Readable,
 * but everything carried the same weight, so finding the one figure a person
 * actually opened the file for meant reading all of it.
 *
 *   band     who issued it and which document this is — the two questions asked
 *            before any number is looked at
 *   meta     who it is for and whether it is settled, as labelled pairs
 *   summary  the figures that get quoted, in boxes, with the one that settles
 *            the account given the accent
 *   table    the lines, with a filled header and banded rows so the eye keeps
 *            its place across a wide row
 *   totals   the arithmetic, right-aligned under the table it belongs to
 *   footer   the business's own words, on every page
 *
 * The band, meta strip, note panel and footer live in `documentChrome.js` —
 * they are what ALL of this system's paperwork looks like, not what an invoice
 * looks like, and the activity record uses the same ones.
 */
export function writeInvoicePdf({ stream, business, template, order, items, payments = [] }) {
  const doc = new PDFDocument({ size: "A4", margin: PAGE_MARGIN });
  doc.pipe(stream);

  const currency = template.currency || business.currency || "";
  const fields = template.fields;
  const { left, right, contentWidth } = geometry(doc);
  const drawFooter = attachFooter(doc, { business, footerText: template.footerText });

  drawBand(doc, {
    business,
    title: template.invoiceTitle || "INVOICE",
    identity: [`No. ${order.orderNumber ?? ""}`, formatDate(order.orderDate ?? order.createdAt, template.dateFormat)],
    showTaxNumber: fields.taxInfo,
  });

  if (template.headerText) {
    doc.font("Helvetica").fontSize(8.5).fillColor(INK_SOFT);
    doc.text(String(template.headerText), left, doc.y, { width: contentWidth });
    doc.y += 8;
  }

  drawMetaStrip(doc, [
    ["Billed to", order.customerName],
    ...(fields.customerAddress && order.customerPhone ? [["Phone", order.customerPhone]] : []),
    // Whether it is settled. There is no `payment_method` on an order — a method
    // belongs to each payment — so this is the honest field to print.
    ["Payment", humanise(order.paymentStatus)],
    ["Status", humanise(order.status)],
  ]);

  // ---- summary: the figures people open the file for --------------------
  //
  // The boxed set is deliberately short. Everything here is also in the totals
  // below; repeating ALL of it would make the summary a second table rather
  // than a glance.
  const cards = [
    { label: "Subtotal", value: order.subtotal },
    { label: "Discount", value: order.discountAmount },
    { label: "Tax", value: order.taxAmount },
    { label: "Total", value: order.grandTotal, accent: true },
  ];

  const cardGap = 8;
  const cardWidth = (contentWidth - cardGap * (cards.length - 1)) / cards.length;
  const cardTop = doc.y;
  const cardHeight = 46;
  cards.forEach((card, index) => {
    const x = left + index * (cardWidth + cardGap);
    doc.save();
    doc.roundedRect(x, cardTop, cardWidth, cardHeight, 4).fill(card.accent ? INK : PAPER_SOFT);
    doc.font("Helvetica").fontSize(7).fillColor(card.accent ? "#C7D4E0" : INK_SOFT);
    doc.text(card.label.toUpperCase(), x + 10, cardTop + 9, { width: cardWidth - 20, lineBreak: false });
    doc.font("Helvetica-Bold").fontSize(12).fillColor(card.accent ? ON_DARK : INK);
    doc.text(money(card.value, currency), x + 10, cardTop + 22, { width: cardWidth - 20, lineBreak: false });
    doc.restore();
  });
  doc.y = cardTop + cardHeight + 20;

  // ---- the lines --------------------------------------------------------
  const columns = fields.itemSku
    ? [
        { key: "productName", label: "Item", width: contentWidth - 330 },
        { key: "sku", label: "SKU", width: 85 },
        { key: "quantity", label: "Qty", width: 45, align: "right" },
        { key: "unitPrice", label: "Price", width: 70, align: "right" },
        { key: "taxAmount", label: "Tax", width: 55, align: "right" },
        { key: "lineTotal", label: "Total", width: 75, align: "right" },
      ]
    : [
        { key: "productName", label: "Item", width: contentWidth - 245 },
        { key: "quantity", label: "Qty", width: 45, align: "right" },
        { key: "unitPrice", label: "Price", width: 70, align: "right" },
        { key: "taxAmount", label: "Tax", width: 55, align: "right" },
        { key: "lineTotal", label: "Total", width: 75, align: "right" },
      ];

  const ROW_HEIGHT = 20;
  const HEADER_HEIGHT = 22;

  const drawTableHeader = () => {
    const top = doc.y;
    doc.save();
    doc.rect(left, top, contentWidth, HEADER_HEIGHT).fill(INK);
    doc.font("Helvetica-Bold").fontSize(8).fillColor(ON_DARK);
    let x = left;
    for (const column of columns) {
      doc.text(column.label.toUpperCase(), x + 8, top + 7, {
        width: column.width - 16,
        align: column.align ?? "left",
        lineBreak: false,
      });
      x += column.width;
    }
    doc.restore();
    doc.y = top + HEADER_HEIGHT;
  };

  const drawRow = (values, index) => {
    const top = doc.y;
    doc.save();
    // Banded, so the eye keeps its line across a wide row.
    if (index % 2 === 1) doc.rect(left, top, contentWidth, ROW_HEIGHT).fill(PAPER_SOFT);
    doc.font("Helvetica").fontSize(9).fillColor(INK);
    let x = left;
    for (const column of columns) {
      doc.text(String(values[column.key] ?? ""), x + 8, top + 6, {
        width: column.width - 16,
        align: column.align ?? "left",
        lineBreak: false,
      });
      x += column.width;
    }
    doc.restore();
    doc.y = top + ROW_HEIGHT;
  };

  drawTableHeader();
  items.forEach((item, index) => {
    // A page break mid-table must not cut a row in half, and the new page needs
    // its own header or the columns become unlabelled.
    if (doc.y > doc.page.height - PAGE_MARGIN - FOOTER_SPACE - ROW_HEIGHT) {
      doc.addPage();
      doc.y = PAGE_MARGIN;
      drawTableHeader();
    }
    drawRow(
      {
        productName: item.productName ?? "",
        sku: item.sku ?? "",
        quantity: Number(item.quantity ?? 0),
        unitPrice: money(item.unitPrice, ""),
        taxAmount: money(item.taxAmount, ""),
        lineTotal: money(item.lineTotal, ""),
      },
      index
    );
  });

  doc.moveTo(left, doc.y).lineTo(right, doc.y).lineWidth(0.5).strokeColor(RULE).stroke();
  doc.y += 12;

  // ---- totals -----------------------------------------------------------
  const totalsWidth = 240;
  const totalsLeft = right - totalsWidth;
  const totalRow = (label, value, { strong = false, accent = false } = {}) => {
    if (doc.y > doc.page.height - PAGE_MARGIN - FOOTER_SPACE - 20) {
      doc.addPage();
      doc.y = PAGE_MARGIN;
    }
    const top = doc.y;
    doc.save();
    if (accent) doc.roundedRect(totalsLeft, top - 3, totalsWidth, 22, 3).fill(PAPER_SOFT);
    doc.font(strong ? "Helvetica-Bold" : "Helvetica").fontSize(strong ? 11 : 9.5);
    doc.fillColor(strong ? INK : INK_SOFT);
    doc.text(label, totalsLeft + 8, top + 2, { width: totalsWidth / 2 - 8, align: "left", lineBreak: false });
    doc.fillColor(INK);
    doc.text(money(value, currency), totalsLeft + totalsWidth / 2, top + 2, {
      width: totalsWidth / 2 - 8,
      align: "right",
      lineBreak: false,
    });
    doc.restore();
    doc.y = top + (strong ? 22 : 16);
  };

  totalRow("Subtotal", order.subtotal);
  if (Number(order.discountAmount) > 0) totalRow("Discount", order.discountAmount);
  if (Number(order.taxAmount) > 0) totalRow("Tax", order.taxAmount);
  if (Number(order.extraCharges) > 0) totalRow("Other charges", order.extraCharges);
  totalRow("Total", order.grandTotal, { strong: true, accent: true });
  totalRow("Paid", order.paidAmount);
  totalRow("Balance", order.remainingAmount, { strong: true });

  // ---- payments, when there are any -------------------------------------
  if (payments.length > 0) {
    doc.y += 10;
    doc.font("Helvetica-Bold").fontSize(8).fillColor(INK_SOFT);
    doc.text("PAYMENTS", left, doc.y, { width: contentWidth, lineBreak: false });
    doc.y += 14;
    doc.font("Helvetica").fontSize(9).fillColor(INK);
    for (const payment of payments) {
      if (doc.y > doc.page.height - PAGE_MARGIN - FOOTER_SPACE - 16) {
        doc.addPage();
        doc.y = PAGE_MARGIN;
      }
      const parts = [
        formatDate(payment.paidAt, template.dateFormat),
        humanise(payment.method),
        money(payment.amount, currency),
        payment.reference ? `(${payment.reference})` : "",
      ].filter(Boolean);
      doc.text(parts.join("   "), left, doc.y, { width: contentWidth, lineBreak: false });
      doc.y += 13;
    }
  }

  // ---- the business's own words -----------------------------------------
  doc.y += 12;
  drawNotePanel(doc, [
    fields.paymentTerms ? template.paymentTerms : null,
    fields.returnPolicy ? template.returnPolicy : null,
    fields.thankYou ? template.thankYouMessage : null,
  ]);

  if (fields.signature && template.signatureText) {
    doc.y += 24;
    if (doc.y > doc.page.height - PAGE_MARGIN - FOOTER_SPACE - 40) {
      doc.addPage();
      doc.y = PAGE_MARGIN;
    }
    const signTop = doc.y;
    doc.font("Helvetica").fontSize(9).fillColor(INK);
    doc.moveTo(right - 200, signTop).lineTo(right, signTop).lineWidth(0.5).strokeColor(RULE).stroke();
    doc.text(String(template.signatureText), right - 200, signTop + 6, {
      width: 200,
      align: "center",
      lineBreak: false,
    });
  }

  // The first page never fired `pageAdded`, so its footer is drawn here.
  drawFooter();

  doc.end();
  return doc;
}
