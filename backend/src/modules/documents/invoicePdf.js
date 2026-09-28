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
 */

const PAGE_MARGIN = 48;
const LINE_GAP = 4;

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
  const right = doc.page.width - PAGE_MARGIN;

  // ---- header ----------------------------------------------------------
  doc.fontSize(20).text(template.invoiceTitle || "INVOICE", { align: "left" });
  doc.moveDown(0.2);

  doc.fontSize(10);
  doc.text(business.name, { continued: false });
  for (const line of [business.address, business.city, business.country, business.phone, business.email]) {
    if (line) doc.text(String(line));
  }
  if (fields.taxInfo && business.tax_number) doc.text(`Tax number: ${business.tax_number}`);

  if (template.headerText) {
    doc.moveDown(0.4);
    doc.fontSize(9).fillColor("#555").text(template.headerText);
    doc.fillColor("#000");
  }

  // The document's own identity, top right, where an invoice is read from.
  const identityTop = PAGE_MARGIN;
  doc.fontSize(10);
  doc.text(`No.  ${order.orderNumber}`, PAGE_MARGIN, identityTop, { align: "right", width: right - PAGE_MARGIN });
  doc.text(`Date  ${formatDate(order.orderDate ?? order.createdAt, template.dateFormat)}`, {
    align: "right",
    width: right - PAGE_MARGIN,
  });
  doc.text(`Status  ${order.status}`, { align: "right", width: right - PAGE_MARGIN });

  doc.moveDown(1.5);

  // ---- who it is for ---------------------------------------------------
  if (order.customerName) {
    doc.fontSize(9).fillColor("#555").text("BILL TO");
    doc.fillColor("#000").fontSize(11).text(order.customerName);
    if (fields.customerAddress) {
      for (const line of [order.customerPhone].filter(Boolean)) doc.fontSize(10).text(String(line));
    }
    doc.moveDown(0.8);
  }

  // ---- the lines -------------------------------------------------------
  const columns = fields.itemSku
    ? [
        { key: "productName", label: "Item", width: 190 },
        { key: "sku", label: "SKU", width: 80 },
        { key: "quantity", label: "Qty", width: 45, align: "right" },
        { key: "unitPrice", label: "Price", width: 70, align: "right", money: true },
        { key: "taxAmount", label: "Tax", width: 55, align: "right", money: true },
        { key: "lineTotal", label: "Total", width: 75, align: "right", money: true },
      ]
    : [
        { key: "productName", label: "Item", width: 265 },
        { key: "quantity", label: "Qty", width: 50, align: "right" },
        { key: "unitPrice", label: "Price", width: 80, align: "right", money: true },
        { key: "taxAmount", label: "Tax", width: 60, align: "right", money: true },
        { key: "lineTotal", label: "Total", width: 80, align: "right", money: true },
      ];

  const drawRow = (values, { bold = false } = {}) => {
    const top = doc.y;
    let x = PAGE_MARGIN;
    doc.fontSize(bold ? 9 : 10).fillColor(bold ? "#555" : "#000");
    for (const column of columns) {
      doc.text(String(values[column.key] ?? ""), x, top, {
        width: column.width,
        align: column.align ?? "left",
        lineBreak: false,
      });
      x += column.width;
    }
    doc.fillColor("#000");
    doc.y = top + (bold ? 14 : 16) + LINE_GAP;
  };

  drawRow(Object.fromEntries(columns.map((c) => [c.key, c.label])), { bold: true });
  doc
    .moveTo(PAGE_MARGIN, doc.y - LINE_GAP / 2)
    .lineTo(right, doc.y - LINE_GAP / 2)
    .strokeColor("#ccc")
    .stroke();

  for (const item of items) {
    // A page break mid-table must not cut a row in half.
    if (doc.y > doc.page.height - PAGE_MARGIN - 140) {
      doc.addPage();
      drawRow(Object.fromEntries(columns.map((c) => [c.key, c.label])), { bold: true });
    }
    drawRow({
      productName: item.productName ?? "",
      sku: item.sku ?? "",
      quantity: Number(item.quantity ?? 0),
      unitPrice: money(item.unitPrice, ""),
      taxAmount: money(item.taxAmount, ""),
      lineTotal: money(item.lineTotal, ""),
    });
  }

  // ---- totals ----------------------------------------------------------
  doc.moveTo(PAGE_MARGIN, doc.y).lineTo(right, doc.y).strokeColor("#ccc").stroke();
  doc.moveDown(0.5);

  const totalRow = (label, value, { bold = false } = {}) => {
    const top = doc.y;
    doc.fontSize(bold ? 12 : 10);
    doc.text(label, right - 260, top, { width: 160, align: "right" });
    doc.text(money(value, currency), right - 100, top, { width: 100, align: "right" });
    doc.y = top + (bold ? 18 : 15);
  };

  totalRow("Subtotal", order.subtotal);
  if (Number(order.discountAmount) > 0) totalRow("Discount", order.discountAmount);
  if (Number(order.taxAmount) > 0) totalRow("Tax", order.taxAmount);
  if (Number(order.extraCharges) > 0) totalRow("Other charges", order.extraCharges);
  totalRow("Total", order.grandTotal, { bold: true });
  totalRow("Paid", order.paidAmount);
  totalRow("Balance", order.remainingAmount, { bold: true });

  // ---- payments, when there are any -----------------------------------
  if (payments.length > 0) {
    doc.moveDown(1);
    doc.fontSize(9).fillColor("#555").text("PAYMENTS");
    doc.fillColor("#000").fontSize(10);
    for (const payment of payments) {
      const method = String(payment.method ?? "").replace(/_/g, " ");
      doc.text(
        `${formatDate(payment.paidAt, template.dateFormat)}  ${method}  ${money(payment.amount, currency)}${
          payment.reference ? `  (${payment.reference})` : ""
        }`
      );
    }
  }

  // ---- the business's own words ---------------------------------------
  doc.moveDown(1.2);
  doc.fontSize(9).fillColor("#333");
  if (fields.paymentTerms && template.paymentTerms) doc.text(template.paymentTerms);
  if (fields.returnPolicy && template.returnPolicy) doc.text(template.returnPolicy);
  if (fields.thankYou && template.thankYouMessage) {
    doc.moveDown(0.4);
    doc.text(template.thankYouMessage);
  }

  if (fields.signature && template.signatureText) {
    doc.moveDown(2);
    doc.fillColor("#000").text(template.signatureText);
    doc.text("______________________________");
  }

  if (template.footerText) {
    doc.fontSize(8).fillColor("#777");
    doc.text(template.footerText, PAGE_MARGIN, doc.page.height - PAGE_MARGIN - 10, {
      width: right - PAGE_MARGIN,
      align: "center",
    });
  }

  doc.end();
  return doc;
}
