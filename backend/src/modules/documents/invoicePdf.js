import PDFDocument from "pdfkit";

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
 *   meta     who it is for and how it was paid, as labelled pairs
 *   summary  the figures that get quoted, in boxes, with the one that settles
 *            the account given the accent
 *   table    the lines, with a filled header and banded rows so the eye keeps
 *            its place across a wide row
 *   totals   the arithmetic, right-aligned under the table it belongs to
 *   footer   the business's own words, on every page
 */

const PAGE_MARGIN = 44;
const BAND_HEIGHT = 86;
const FOOTER_SPACE = 64;

/** Ink, fills and rules. One place, so the document stays of a piece. */
const INK = "#14304A";
const INK_SOFT = "#5A6B7C";
const PAPER_SOFT = "#F1F5F9";
const RULE = "#D8E0E8";
const ACCENT = "#0F766E";
const ON_DARK = "#FFFFFF";

/** Right-aligned money in a fixed column, so the decimal points line up. */
function money(value, currency) {
  const amount = Number(value ?? 0).toFixed(2);
  return currency ? `${amount} ${currency}` : amount;
}

function formatDate(value, format) {
  if (!value) return "";
  const date = value instanceof Date ? value : new Date(String(value).replace(" ", "T"));
  if (Number.isNaN(date.getTime())) return String(value);

  const yyyy = date.getFullYear();
  const mm = String(date.getMonth() + 1).padStart(2, "0");
  const dd = String(date.getDate()).padStart(2, "0");

  switch (format) {
    case "DD/MM/YYYY":
      return `${dd}/${mm}/${yyyy}`;
    case "MM/DD/YYYY":
      return `${mm}/${dd}/${yyyy}`;
    default:
      return `${yyyy}-${mm}-${dd}`;
  }
}

/** Status reads as a word, not as a column name: `partially_paid` → `Partially paid`. */
function humanise(value) {
  const text = String(value ?? "").replace(/_/g, " ").trim();
  if (!text) return "";
  return text.charAt(0).toUpperCase() + text.slice(1);
}

/**
 * Writes an order's invoice into `stream`.
 *
 * @param {object} args
 * @param {import('node:stream').Writable} args.stream
 * @param {object} args.business   the businesses row
 * @param {object} args.template   templateView()'s shape
 * @param {object} args.order      orderView()'s shape
 * @param {object[]} args.items    the order's lines, as stored
 * @param {object[]} [args.payments]
 */
export function writeInvoicePdf({ stream, business, template, order, items, payments = [] }) {
  const doc = new PDFDocument({ size: "A4", margin: PAGE_MARGIN });
  doc.pipe(stream);

  const currency = template.currency || business.currency || "";
  const fields = template.fields;
  const left = PAGE_MARGIN;
  const right = doc.page.width - PAGE_MARGIN;
  const contentWidth = right - left;

  /** The business's own words, pinned to the bottom of whichever page we are on. */
  const drawFooter = () => {
    const y = doc.page.height - PAGE_MARGIN - 22;
    doc.save();
    doc.moveTo(left, y - 10).lineTo(right, y - 10).lineWidth(0.5).strokeColor(RULE).stroke();
    const contact = [business.name, business.phone, business.email].filter(Boolean).join("  ·  ");
    doc.font("Helvetica").fontSize(7.5).fillColor(INK_SOFT);
    doc.text(contact, left, y, { width: contentWidth, align: "left", lineBreak: false });
    if (template.footerText) {
      doc.text(String(template.footerText), left, y + 10, { width: contentWidth, align: "left", lineBreak: false });
    }
    doc.restore();
  };

  // Every page gets the footer, including ones a long table creates.
  doc.on("pageAdded", drawFooter);

  // ---- the band: who issued it, and which document this is --------------
  doc.save();
  doc.rect(0, 0, doc.page.width, BAND_HEIGHT).fill(INK);

  doc.font("Helvetica-Bold").fontSize(16).fillColor(ON_DARK);
  doc.text(String(business.name ?? ""), left, 22, { width: contentWidth * 0.55, lineBreak: false });

  const issuerLines = [business.address, business.city, business.country].filter(Boolean).join(", ");
  doc.font("Helvetica").fontSize(8).fillColor("#C7D4E0");
  if (issuerLines) doc.text(issuerLines, left, 44, { width: contentWidth * 0.55, lineBreak: false });
  const issuerContact = [business.phone, business.email].filter(Boolean).join("  ·  ");
  if (issuerContact) doc.text(issuerContact, left, 55, { width: contentWidth * 0.55, lineBreak: false });
  if (fields.taxInfo && business.tax_number) {
    doc.text(`Tax number: ${business.tax_number}`, left, 66, { width: contentWidth * 0.55, lineBreak: false });
  }

  // The document's own identity, top right, where an invoice is read from.
  const idWidth = contentWidth * 0.4;
  const idLeft = right - idWidth;
  doc.font("Helvetica-Bold").fontSize(15).fillColor(ON_DARK);
  doc.text(String(template.invoiceTitle || "INVOICE").toUpperCase(), idLeft, 22, {
    width: idWidth,
    align: "right",
    lineBreak: false,
  });
  doc.font("Helvetica").fontSize(9).fillColor("#C7D4E0");
  doc.text(`No. ${order.orderNumber ?? ""}`, idLeft, 44, { width: idWidth, align: "right", lineBreak: false });
  doc.text(formatDate(order.orderDate ?? order.createdAt, template.dateFormat), idLeft, 56, {
    width: idWidth,
    align: "right",
    lineBreak: false,
  });
  doc.restore();

  doc.y = BAND_HEIGHT + 18;

  if (template.headerText) {
    doc.font("Helvetica").fontSize(8.5).fillColor(INK_SOFT);
    doc.text(String(template.headerText), left, doc.y, { width: contentWidth });
    doc.y += 8;
  }

  // ---- meta: who it is for, and how it was settled ----------------------
  const meta = [
    ["Billed to", order.customerName || "—"],
    ...(fields.customerAddress && order.customerPhone ? [["Phone", order.customerPhone]] : []),
    ["Payment", humanise(order.paymentStatus) || "—"],
    ["Status", humanise(order.status) || "—"],
  ];

  const metaTop = doc.y;
  const metaWidth = contentWidth / meta.length;
  meta.forEach(([label, value], index) => {
    const x = left + index * metaWidth;
    doc.font("Helvetica").fontSize(7).fillColor(INK_SOFT);
    doc.text(label.toUpperCase(), x, metaTop, { width: metaWidth - 8, lineBreak: false });
    doc.font("Helvetica-Bold").fontSize(10).fillColor(INK);
    doc.text(String(value), x, metaTop + 11, { width: metaWidth - 8, lineBreak: false });
  });
  doc.y = metaTop + 34;
  doc.moveTo(left, doc.y).lineTo(right, doc.y).lineWidth(0.5).strokeColor(RULE).stroke();
  doc.y += 16;

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
  const notes = [
    fields.paymentTerms ? template.paymentTerms : null,
    fields.returnPolicy ? template.returnPolicy : null,
    fields.thankYou ? template.thankYouMessage : null,
  ].filter(Boolean);

  if (notes.length > 0) {
    doc.y += 12;
    if (doc.y > doc.page.height - PAGE_MARGIN - FOOTER_SPACE - 40) {
      doc.addPage();
      doc.y = PAGE_MARGIN;
    }
    doc.save();
    const notesTop = doc.y;
    doc.font("Helvetica").fontSize(8.5).fillColor(INK_SOFT);
    const notesHeight = notes.reduce(
      (sum, note) => sum + doc.heightOfString(String(note), { width: contentWidth - 24 }) + 3,
      14
    );
    doc.roundedRect(left, notesTop, contentWidth, notesHeight, 4).fill(PAPER_SOFT);
    doc.fillColor(INK_SOFT);
    let noteY = notesTop + 8;
    for (const note of notes) {
      doc.text(String(note), left + 12, noteY, { width: contentWidth - 24 });
      noteY = doc.y + 3;
    }
    doc.restore();
    doc.y = notesTop + notesHeight + 6;
  }

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
