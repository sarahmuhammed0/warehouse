import { Router } from "express";
import { z } from "zod";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
import { auditTrail } from "../../middleware/auditTrail.js";
import { validate } from "../../middleware/validate.js";
import { requiredString, optionalString, enumSchema } from "../../validation/common.js";
import { ok } from "../../utils/responseEnvelope.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import { pool, runInTransaction } from "../../db/pool.js";
import { DOCUMENT_TYPES as DOCUMENT_PREFIXES } from "../documents/numbering.js";

const tenant = (req) => req.auth.businessId;

/**
 * §34's Business Information, and §29's numbering — the two Settings sections
 * that are NOT key/value.
 *
 * A business's name, currency and address are columns on `businesses`, and its
 * document prefixes are rows in `document_sequences`. Storing either as a
 * setting key would mean two places holding the same fact: `businesses.currency`
 * is what every money column is denominated in, and `document_sequences.prefix`
 * is what `nextDocumentNumber` actually reads. A copy under a settings key would
 * be the one the UI edited and the one nothing used.
 */

const profileView = (row) => ({
  id: row.id,
  name: row.name,
  businessType: row.business_type,
  logoUrl: row.logo_url,
  description: row.description,
  phone: row.phone,
  phoneSecondary: row.phone_secondary,
  email: row.email,
  address: row.address,
  city: row.city,
  country: row.country,
  website: row.website,
  taxNumber: row.tax_number,
  registrationNumber: row.registration_number,
  currency: row.currency,
  language: row.language,
  timezone: row.timezone,
  status: row.status,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

const BUSINESS_TYPES = [
  "furniture_factory",
  "general_factory",
  "warehouse",
  "storage_store",
  "wholesale_store",
  "distribution_center",
  "custom",
];

const updateProfileSchema = z
  .object({
    name: optionalString(150),
    // §6's business type drives which modules a business sees, so it is editable
    // — a storage store that starts manufacturing should not need a new account.
    businessType: enumSchema(BUSINESS_TYPES, "Business type").optional(),
    logoUrl: optionalString(500),
    description: optionalString(5000),
    phoneSecondary: optionalString(20),
    email: optionalString(255),
    address: optionalString(255),
    city: optionalString(100),
    country: optionalString(100),
    website: optionalString(255),
    taxNumber: optionalString(100),
    registrationNumber: optionalString(100),
    // ISO 4217, three letters. Upper-cased so "usd" and "USD" are the same
    // currency rather than two.
    currency: z
      .string()
      .trim()
      .length(3, "A currency is a three-letter code, e.g. USD.")
      .transform((value) => value.toUpperCase())
      .optional(),
    language: optionalString(10),
    timezone: optionalString(64),
  })
  .refine((value) => Object.values(value).some((v) => v !== undefined), {
    message: "Provide at least one field to update.",
  });

const COLUMNS = {
  name: "name",
  businessType: "business_type",
  logoUrl: "logo_url",
  description: "description",
  phoneSecondary: "phone_secondary",
  email: "email",
  address: "address",
  city: "city",
  country: "country",
  website: "website",
  taxNumber: "tax_number",
  registrationNumber: "registration_number",
  currency: "currency",
  language: "language",
  timezone: "timezone",
};

export const businessProfileRouter = Router();
businessProfileRouter.use(authenticate, requireAccountType("business_user"), auditTrail("settings"));

/**
 * The business's own profile. Readable with `settings.view`, which is the
 * owner's by default — the name and logo appear on every document anyway, but
 * the tax number and registration number are not an employee's business.
 *
 * The PHONE is not editable here: it is the business's identity for a System
 * Admin's approval queue and is unique across the platform, so changing it is
 * an admin action (§57), not a self-service one.
 */
businessProfileRouter.get("/", authorize("settings.view"), async (req, res, next) => {
  try {
    const [rows] = await pool.query(
      `SELECT * FROM businesses WHERE id = ? AND deleted_at IS NULL LIMIT 1`,
      [tenant(req)]
    );
    if (rows.length === 0) throw errors.notFound("business");
    res.json(ok(profileView(rows[0])));
  } catch (err) {
    next(err);
  }
});

businessProfileRouter.patch(
  "/",
  authorize("settings.edit"),
  validate(updateProfileSchema),
  async (req, res, next) => {
    try {
      const businessId = tenant(req);

      const sets = [];
      const params = [];
      for (const [key, column] of Object.entries(COLUMNS)) {
        if (req.body[key] === undefined) continue;
        sets.push(`${column} = ?`);
        params.push(req.body[key]);
      }

      await runInTransaction(async (conn) => {
        const [result] = await conn.query(
          `UPDATE businesses SET ${sets.join(", ")}, updated_at = NOW()
            WHERE id = ? AND deleted_at IS NULL`,
          [...params, businessId]
        );
        if (result.affectedRows === 0) throw errors.notFound("business");
      });

      const [rows] = await pool.query(`SELECT * FROM businesses WHERE id = ? LIMIT 1`, [businessId]);
      res.json(ok(profileView(rows[0])));
    } catch (err) {
      next(toAppError(err, { constraintMessages: { uq_businesses_phone: "That phone number is already registered." } }) ?? err);
    }
  }
);

// ---- §29's document numbering -------------------------------------------

// The types `nextDocumentNumber` can actually allocate, taken from its own map
// rather than restated here. The column's enum also has `invoice`, which nothing
// allocates — a sale IS the invoice (§13) and is numbered INV — so offering it on
// a settings screen would be offering a setting with no effect.
const DOCUMENT_TYPES = Object.keys(DOCUMENT_PREFIXES);

const numberingView = (row) => ({
  documentType: row.document_type,
  prefix: row.prefix,
  nextNumber: Number(row.next_number),
  numberPadding: Number(row.number_padding),
  includeYear: Boolean(row.include_year),
  currentYear: row.current_year === null ? null : Number(row.current_year),
  // What the next document will actually be called, which is the only part of
  // this a person can check at a glance.
  example: formatExample(row),
});

function formatExample(row) {
  const parts = [row.prefix];
  if (row.include_year) parts.push(String(row.current_year ?? new Date().getFullYear()));
  parts.push(String(row.next_number).padStart(Number(row.number_padding), "0"));
  return parts.join("-");
}

const numberingSchema = z
  .object({
    prefix: requiredString(20, "A prefix").optional(),
    numberPadding: z.coerce.number().int().min(1).max(12).optional(),
    includeYear: z.boolean().optional(),
    // Moving the counter FORWARD only. A business migrating from another system
    // needs to continue its own numbering; being allowed to move it back would
    // hand out a number twice, and §61 requires a document number to be unique
    // for as long as the documents exist.
    nextNumber: z.coerce.number().int().min(1).optional(),
  })
  .refine((value) => Object.values(value).some((v) => v !== undefined), {
    message: "Provide at least one field to update.",
  });

export const numberingRouter = Router();
numberingRouter.use(authenticate, requireAccountType("business_user"), auditTrail("settings"));

numberingRouter.get("/numbering", authorize("settings.view"), async (req, res, next) => {
  try {
    const businessId = tenant(req);
    const [rows] = await pool.query(
      `SELECT * FROM document_sequences WHERE business_id = ? ORDER BY document_type`,
      [businessId]
    );

    // A sequence row is created on first use, not up front (see numbering.js),
    // so a type nobody has numbered yet has no row. It is still reported, with
    // the defaults it would be created with — otherwise the screen would show
    // nothing to configure until the first document existed.
    const byType = new Map(rows.map((row) => [row.document_type, row]));
    const year = new Date().getFullYear();

    res.json(
      ok(
        DOCUMENT_TYPES.map((documentType) =>
          numberingView(
            byType.get(documentType) ?? {
              document_type: documentType,
              prefix: DOCUMENT_PREFIXES[documentType],
              next_number: 1,
              number_padding: 6,
              include_year: true,
              current_year: year,
            }
          )
        )
      )
    );
  } catch (err) {
    next(err);
  }
});

numberingRouter.patch(
  "/numbering/:documentType",
  authorize("settings.edit"),
  validate(numberingSchema),
  async (req, res, next) => {
    try {
      const businessId = tenant(req);
      const { documentType } = req.params;
      if (!DOCUMENT_TYPES.includes(documentType)) throw errors.notFound("document type");

      const year = new Date().getFullYear();

      await runInTransaction(async (conn) => {
        // Created if absent, with this business's chosen values — the same
        // upsert-then-read shape `nextDocumentNumber` uses, so configuring a
        // type before its first document works.
        await conn.query(
          `INSERT INTO document_sequences
             (business_id, document_type, prefix, next_number, number_padding, include_year, current_year)
           VALUES (?, ?, ?, 1, 6, TRUE, ?)
           ON DUPLICATE KEY UPDATE updated_at = updated_at`,
          [businessId, documentType, DOCUMENT_PREFIXES[documentType], year]
        );

        const [rows] = await conn.query(
          `SELECT * FROM document_sequences WHERE business_id = ? AND document_type = ? LIMIT 1 FOR UPDATE`,
          [businessId, documentType]
        );
        const current = rows[0];

        if (req.body.nextNumber !== undefined && req.body.nextNumber < Number(current.next_number)) {
          throw errors.validation(
            `The counter is already at ${current.next_number}; it can only be moved forward, or a number would be issued twice.`
          );
        }

        const sets = [];
        const params = [];
        const columns = {
          prefix: "prefix",
          numberPadding: "number_padding",
          includeYear: "include_year",
          nextNumber: "next_number",
        };
        for (const [key, column] of Object.entries(columns)) {
          if (req.body[key] === undefined) continue;
          sets.push(`${column} = ?`);
          params.push(req.body[key]);
        }

        await conn.query(
          `UPDATE document_sequences SET ${sets.join(", ")}, updated_at = NOW() WHERE id = ?`,
          [...params, current.id]
        );
      });

      const [rows] = await pool.query(
        `SELECT * FROM document_sequences WHERE business_id = ? AND document_type = ? LIMIT 1`,
        [businessId, documentType]
      );
      res.json(ok(numberingView(rows[0])));
    } catch (err) {
      next(toAppError(err) ?? err);
    }
  }
);
