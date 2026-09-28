import { pool } from "../../db/pool.js";

/**
 * §28's PDF template — what a business's documents say around the numbers.
 *
 * A TABLE, not settings keys. `pdf_templates` already exists with a column per
 * field, it is per business, and §28 allows more than one (a quote and an
 * invoice may read differently). Flattening it into `business_settings` would
 * mean fifteen keys that only ever change together, and no way to have a second
 * template later.
 *
 * `enabled_fields` is JSON for the optional blocks — which sections appear at
 * all — because that list grows with the document design and a column per
 * checkbox would need a migration each time.
 */

/** The blocks a business can switch off, and whether they start on. */
export const TEMPLATE_FIELDS = {
  logo: true,
  taxInfo: true,
  signature: true,
  paymentTerms: true,
  returnPolicy: false,
  thankYou: true,
  customerAddress: true,
  itemSku: true,
};

const DEFAULTS = {
  name: "Default",
  invoice_title: "INVOICE",
  header_text: null,
  footer_text: "Thank you for your business.",
  thank_you_message: "Thank you for your business.",
  return_policy: null,
  payment_terms: null,
  signature_text: null,
  date_format: "YYYY-MM-DD",
};

export function templateView(row) {
  const enabled = parseFields(row.enabled_fields);
  return {
    id: row.id ?? null,
    name: row.name,
    invoiceTitle: row.invoice_title,
    logoUrl: row.logo_url ?? null,
    headerText: row.header_text,
    footerText: row.footer_text,
    thankYouMessage: row.thank_you_message,
    returnPolicy: row.return_policy,
    paymentTerms: row.payment_terms,
    signatureText: row.signature_text,
    currency: row.currency ?? null,
    dateFormat: row.date_format,
    isDefault: row.is_default === undefined ? true : Boolean(row.is_default),
    fields: enabled,
  };
}

function parseFields(raw) {
  let value = raw;
  if (typeof raw === "string") {
    try {
      value = JSON.parse(raw);
    } catch {
      value = null;
    }
  }
  // Unknown keys are dropped and missing ones default, so an older row and a
  // newer build cannot disagree about what a template says.
  const result = {};
  for (const [key, on] of Object.entries(TEMPLATE_FIELDS)) {
    result[key] = value && typeof value === "object" && key in value ? Boolean(value[key]) : on;
  }
  return result;
}

/**
 * The business's default template, or the built-in one.
 *
 * Never returns null: a document must be printable before anyone has visited the
 * settings screen, and refusing to print because no template row exists would be
 * a configuration error dressed up as a missing feature.
 */
export async function defaultTemplate({ businessId, conn = pool }) {
  const [rows] = await conn.query(
    `SELECT * FROM pdf_templates
      WHERE business_id = ? AND deleted_at IS NULL
      ORDER BY is_default DESC, id ASC LIMIT 1`,
    [businessId]
  );
  if (rows.length > 0) return rows[0];

  return { ...DEFAULTS, business_id: businessId, enabled_fields: null, is_default: true, currency: null };
}

const COLUMNS = {
  name: "name",
  invoiceTitle: "invoice_title",
  logoUrl: "logo_url",
  headerText: "header_text",
  footerText: "footer_text",
  thankYouMessage: "thank_you_message",
  returnPolicy: "return_policy",
  paymentTerms: "payment_terms",
  signatureText: "signature_text",
  currency: "currency",
  dateFormat: "date_format",
};

/**
 * Writes the business's default template, creating it on first save.
 *
 * An upsert rather than create-then-update, because the settings screen has no
 * notion of "the template does not exist yet" — it shows the effective values and
 * saves them, and the first save is the one that materialises the row.
 */
export async function saveDefaultTemplate(conn, { businessId, data }) {
  const existing = await defaultTemplate({ businessId, conn });
  const merged = { ...existing };

  for (const [key, column] of Object.entries(COLUMNS)) {
    if (data[key] !== undefined) merged[column] = data[key];
  }

  const fields = { ...parseFields(existing.enabled_fields) };
  if (data.fields) {
    for (const [key, value] of Object.entries(data.fields)) {
      if (key in TEMPLATE_FIELDS) fields[key] = Boolean(value);
    }
  }

  if (existing.id) {
    await conn.query(
      `UPDATE pdf_templates
          SET name = ?, invoice_title = ?, logo_url = ?, header_text = ?, footer_text = ?,
              thank_you_message = ?, return_policy = ?, payment_terms = ?, signature_text = ?,
              currency = ?, date_format = ?, enabled_fields = CAST(? AS JSON), updated_at = NOW()
        WHERE id = ? AND business_id = ?`,
      [
        merged.name,
        merged.invoice_title,
        merged.logo_url ?? null,
        merged.header_text,
        merged.footer_text,
        merged.thank_you_message,
        merged.return_policy,
        merged.payment_terms,
        merged.signature_text,
        merged.currency ?? null,
        merged.date_format,
        JSON.stringify(fields),
        existing.id,
        businessId,
      ]
    );
    return existing.id;
  }

  const [result] = await conn.query(
    `INSERT INTO pdf_templates
       (business_id, name, invoice_title, logo_url, header_text, footer_text,
        thank_you_message, return_policy, payment_terms, signature_text, currency,
        date_format, enabled_fields, is_default)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CAST(? AS JSON), TRUE)`,
    [
      businessId,
      merged.name,
      merged.invoice_title,
      merged.logo_url ?? null,
      merged.header_text,
      merged.footer_text,
      merged.thank_you_message,
      merged.return_policy,
      merged.payment_terms,
      merged.signature_text,
      merged.currency ?? null,
      merged.date_format,
      JSON.stringify(fields),
    ]
  );
  return result.insertId;
}
