/**
 * The parts every generated document shares: the band it opens with, the row of
 * labelled facts under it, the footer on each page, and the ink they are drawn
 * in.
 *
 * Extracted when the activity trail needed a document of its own. Copying the
 * eighty lines of banner-and-footer would have meant two documents that drift
 * apart one small fix at a time — the invoice gaining a tax number the audit
 * record never shows, the audit record getting a footer the invoice does not.
 * One place, so a change to "what our paperwork looks like" is one change.
 *
 * Nothing here computes a figure or invents a value. Everything is handed in.
 */

export const PAGE_MARGIN = 44;
export const BAND_HEIGHT = 86;
export const FOOTER_SPACE = 64;

/** Ink, fills and rules. One palette, so the paperwork stays of a piece. */
export const INK = "#14304A";
export const INK_SOFT = "#5A6B7C";
export const PAPER_SOFT = "#F1F5F9";
export const RULE = "#D8E0E8";
export const ON_DARK = "#FFFFFF";
export const BAND_SUBTLE = "#C7D4E0";

/** Right-aligned money in a fixed column, so the decimal points line up. */
export function money(value, currency) {
  const amount = Number(value ?? 0).toFixed(2);
  return currency ? `${amount} ${currency}` : amount;
}

export function formatDate(value, format) {
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

/** The same, with the clock — an audit entry is worthless to the minute only. */
export function formatDateTime(value, format) {
  if (!value) return "";
  const date = value instanceof Date ? value : new Date(String(value).replace(" ", "T"));
  if (Number.isNaN(date.getTime())) return String(value);
  const hh = String(date.getHours()).padStart(2, "0");
  const mi = String(date.getMinutes()).padStart(2, "0");
  const ss = String(date.getSeconds()).padStart(2, "0");
  return `${formatDate(date, format)} ${hh}:${mi}:${ss}`;
}

/** `partially_paid` → `Partially paid`: a word, not a column name. */
export function humanise(value) {
  const text = String(value ?? "").replace(/_/g, " ").trim();
  if (!text) return "";
  return text.charAt(0).toUpperCase() + text.slice(1);
}

/**
 * An audit action without the module it is already sitting next to.
 *
 * The trail stores `auth.login_success`, and the module is printed in its own
 * column — so the raw value reads "Auth.login success" beside a column already
 * saying "Auth". The prefix is dropped rather than the column, because the
 * module is the useful one when scanning.
 */
export function actionLabel(value) {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  const withoutModule = raw.includes(".") ? raw.slice(raw.indexOf(".") + 1) : raw;
  return humanise(withoutModule);
}

/** The page's usable edges, worked out once per document. */
export function geometry(doc) {
  const left = PAGE_MARGIN;
  const right = doc.page.width - PAGE_MARGIN;
  return { left, right, contentWidth: right - left };
}

/**
 * Who issued it, and which document this is.
 *
 * Both halves matter and both are read before any figure below: the business on
 * the left, the document's own identity on the right, where a reader's eye goes
 * for a number and a date.
 */
export function drawBand(doc, { business, title, identity = [], showTaxNumber = false }) {
  const { left, right, contentWidth } = geometry(doc);

  doc.save();
  doc.rect(0, 0, doc.page.width, BAND_HEIGHT).fill(INK);

  doc.font("Helvetica-Bold").fontSize(16).fillColor(ON_DARK);
  doc.text(String(business.name ?? ""), left, 22, { width: contentWidth * 0.55, lineBreak: false });

  const place = [business.address, business.city, business.country].filter(Boolean).join(", ");
  doc.font("Helvetica").fontSize(8).fillColor(BAND_SUBTLE);
  if (place) doc.text(place, left, 44, { width: contentWidth * 0.55, lineBreak: false });
  const contact = [business.phone, business.email].filter(Boolean).join("  ·  ");
  if (contact) doc.text(contact, left, 55, { width: contentWidth * 0.55, lineBreak: false });
  if (showTaxNumber && business.tax_number) {
    doc.text(`Tax number: ${business.tax_number}`, left, 66, { width: contentWidth * 0.55, lineBreak: false });
  }

  const idWidth = contentWidth * 0.4;
  const idLeft = right - idWidth;
  doc.font("Helvetica-Bold").fontSize(15).fillColor(ON_DARK);
  doc.text(String(title ?? "").toUpperCase(), idLeft, 22, { width: idWidth, align: "right", lineBreak: false });
  doc.font("Helvetica").fontSize(9).fillColor(BAND_SUBTLE);
  identity.forEach((line, index) => {
    doc.text(String(line ?? ""), idLeft, 44 + index * 12, { width: idWidth, align: "right", lineBreak: false });
  });
  doc.restore();

  doc.y = BAND_HEIGHT + 18;
}

/**
 * Returns a footer painter, and wires it to every page added after this call.
 *
 * The first page never fires `pageAdded`, so the caller draws that one itself at
 * the end — once the content is laid out and the page it finished on is known.
 */
export function attachFooter(doc, { business, footerText }) {
  const { left, right, contentWidth } = geometry(doc);

  const draw = () => {
    const y = doc.page.height - PAGE_MARGIN - 22;
    doc.save();
    doc.moveTo(left, y - 10).lineTo(right, y - 10).lineWidth(0.5).strokeColor(RULE).stroke();
    const contact = [business.name, business.phone, business.email].filter(Boolean).join("  ·  ");
    doc.font("Helvetica").fontSize(7.5).fillColor(INK_SOFT);
    doc.text(contact, left, y, { width: contentWidth, align: "left", lineBreak: false });
    if (footerText) {
      doc.text(String(footerText), left, y + 10, { width: contentWidth, align: "left", lineBreak: false });
    }
    doc.restore();
  };

  doc.on("pageAdded", draw);
  return draw;
}

/**
 * A row of labelled facts: small grey label, the value in bold beneath it.
 *
 * `pairs` is `[[label, value], ...]`. An empty value is drawn as an em dash
 * rather than left blank, so a missing fact reads as missing rather than as a
 * layout fault.
 */
export function drawMetaStrip(doc, pairs) {
  const { left, right, contentWidth } = geometry(doc);
  if (pairs.length === 0) return;

  const top = doc.y;
  const columnWidth = contentWidth / pairs.length;
  pairs.forEach(([label, value], index) => {
    const x = left + index * columnWidth;
    doc.font("Helvetica").fontSize(7).fillColor(INK_SOFT);
    doc.text(String(label).toUpperCase(), x, top, { width: columnWidth - 8, lineBreak: false });
    doc.font("Helvetica-Bold").fontSize(10).fillColor(INK);
    doc.text(String(value || "—"), x, top + 11, { width: columnWidth - 8, lineBreak: false });
  });

  doc.y = top + 34;
  doc.moveTo(left, doc.y).lineTo(right, doc.y).lineWidth(0.5).strokeColor(RULE).stroke();
  doc.y += 16;
}

/**
 * A soft panel of prose — terms, a note, the body of a record.
 *
 * Measured before it is filled, so the box is the height of the text rather than
 * a guess the text then spills out of.
 */
export function drawNotePanel(doc, lines) {
  const { left, contentWidth } = geometry(doc);
  const present = lines.filter(Boolean).map(String);
  if (present.length === 0) return;

  if (doc.y > doc.page.height - PAGE_MARGIN - FOOTER_SPACE - 40) {
    doc.addPage();
    doc.y = PAGE_MARGIN;
  }

  doc.save();
  const top = doc.y;
  doc.font("Helvetica").fontSize(8.5).fillColor(INK_SOFT);
  const height = present.reduce(
    (sum, line) => sum + doc.heightOfString(line, { width: contentWidth - 24 }) + 3,
    14
  );
  doc.roundedRect(left, top, contentWidth, height, 4).fill(PAPER_SOFT);
  doc.fillColor(INK_SOFT);
  let y = top + 8;
  for (const line of present) {
    doc.text(line, left + 12, y, { width: contentWidth - 24 });
    y = doc.y + 3;
  }
  doc.restore();
  doc.y = top + height + 6;
}
