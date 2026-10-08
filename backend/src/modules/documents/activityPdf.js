import PDFDocument from "pdfkit";

import {
  PAGE_MARGIN,
  INK,
  INK_SOFT,
  PAPER_SOFT,
  RULE,
  attachFooter,
  drawBand,
  drawMetaStrip,
  drawNotePanel,
  formatDateTime,
  geometry,
  humanise,
  actionLabel,
} from "./documentChrome.js";

/**
 * One entry from §30's activity trail, as a filed document.
 *
 * The trail is evidence: who did what, to which record, from where, and when.
 * A printed copy is what gets attached to a dispute or handed to an auditor, so
 * it carries every field the row has rather than a readable summary of them —
 * including the ones a person would not think to ask for, like the IP address
 * and the internal reference, which are the parts that make an entry checkable
 * against anything else.
 *
 * NOTHING IS INTERPRETED HERE. The description is the sentence the trail
 * recorded at the time; this does not re-derive it from today's data, for the
 * same reason the invoice does not re-price an old order.
 *
 * Deterministic, like every other document: no "printed at", no run id, so two
 * copies of one entry are the same file.
 */
export function writeActivityPdf({ stream, business, template, entry }) {
  const doc = new PDFDocument({ size: "A4", margin: PAGE_MARGIN });
  doc.pipe(stream);

  const { left, right, contentWidth } = geometry(doc);
  const dateFormat = template?.dateFormat;
  const drawFooter = attachFooter(doc, { business, footerText: template?.footerText });

  drawBand(doc, {
    business,
    title: "Activity record",
    identity: [`No. ${entry.id}`, formatDateTime(entry.createdAt, dateFormat)],
  });

  drawMetaStrip(doc, [
    ["Who", entry.actorName || "System"],
    ["Module", humanise(entry.module)],
    ["Action", actionLabel(entry.action)],
    ["When", formatDateTime(entry.createdAt, dateFormat)],
  ]);

  // ---- what happened ----------------------------------------------------
  doc.font("Helvetica-Bold").fontSize(8).fillColor(INK_SOFT);
  doc.text("WHAT HAPPENED", left, doc.y, { width: contentWidth, lineBreak: false });
  doc.y += 14;
  drawNotePanel(doc, [entry.description]);

  // ---- the parts that make it checkable ---------------------------------
  //
  // A table of two columns rather than prose: these are looked UP, not read.
  const details = [
    ["Entry", String(entry.id ?? "")],
    ["Performed by", entry.actorName || "System"],
    // A public self-registration has no actor by design; saying "system" and
    // then naming the actor type keeps that distinction rather than hiding it.
    ["Account type", humanise(entry.actorType)],
    ["Module", humanise(entry.module)],
    ["Action", actionLabel(entry.action)],
    ["Record", entry.referenceType ? `${humanise(entry.referenceType)} #${entry.referenceId ?? "—"}` : "—"],
    ["IP address", entry.ipAddress || "—"],
    ["Recorded", formatDateTime(entry.createdAt, dateFormat)],
  ];

  doc.y += 6;
  doc.font("Helvetica-Bold").fontSize(8).fillColor(INK_SOFT);
  doc.text("DETAILS", left, doc.y, { width: contentWidth, lineBreak: false });
  doc.y += 14;

  const ROW = 22;
  const labelWidth = 150;
  details.forEach(([label, value], index) => {
    if (doc.y > doc.page.height - PAGE_MARGIN - 80) {
      doc.addPage();
      doc.y = PAGE_MARGIN;
    }
    const top = doc.y;
    doc.save();
    if (index % 2 === 1) doc.rect(left, top, contentWidth, ROW).fill(PAPER_SOFT);
    doc.font("Helvetica").fontSize(9).fillColor(INK_SOFT);
    doc.text(label, left + 8, top + 7, { width: labelWidth, lineBreak: false });
    doc.font("Helvetica-Bold").fontSize(9).fillColor(INK);
    doc.text(String(value), left + 8 + labelWidth, top + 7, {
      width: contentWidth - labelWidth - 16,
      lineBreak: false,
    });
    doc.restore();
    doc.y = top + ROW;
  });

  doc.moveTo(left, doc.y).lineTo(right, doc.y).lineWidth(0.5).strokeColor(RULE).stroke();
  doc.y += 14;

  // Says what the paper IS, so a copy found on its own is not mistaken for a
  // report somebody compiled.
  doc.font("Helvetica").fontSize(8).fillColor(INK_SOFT);
  doc.text(
    "This is a single entry from the activity trail, reproduced as recorded. The trail is written as a side effect of the action it describes and is never edited.",
    left,
    doc.y,
    { width: contentWidth }
  );

  drawFooter();
  doc.end();
  return doc;
}
