import { Router } from "express";
import { z } from "zod";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
import { auditTrail } from "../../middleware/auditTrail.js";
import { validate, validateRequest } from "../../middleware/validate.js";
import { idParamsSchema, requiredString, optionalString, enumSchema } from "../../validation/common.js";
import { ok } from "../../utils/responseEnvelope.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import { pool, runInTransaction, queryAll } from "../../db/pool.js";

const tenant = (req) => req.auth.businessId;

/**
 * §51's custom fields.
 *
 * DEFINITIONS here, VALUES on the record they belong to. This module owns the
 * first: what extra fields this business keeps, per entity type. The values are
 * read and written with the record itself, because a product's extra fields are
 * part of that product and saving them separately would let the two halves
 * disagree.
 *
 * The entity types are the ones the column's enum allows — a fixed list, not
 * free text, so a definition cannot be attached to a table that does not exist.
 */
const ENTITY_TYPES = ["product", "category", "customer", "supplier", "order", "purchase", "production"];
const FIELD_TYPES = ["text", "number", "date", "boolean", "select", "multiselect"];

const view = (row) => ({
  id: row.id,
  entityType: row.entity_type,
  fieldKey: row.field_key,
  label: row.label,
  fieldType: row.field_type,
  options: parseOptions(row.options),
  isRequired: Boolean(row.is_required),
  isVisible: Boolean(row.is_visible),
  sortOrder: Number(row.sort_order),
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

function parseOptions(raw) {
  if (raw === null || raw === undefined) return null;
  if (Array.isArray(raw)) return raw;
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

const baseSchema = {
  label: requiredString(150, "A label"),
  fieldType: enumSchema(FIELD_TYPES, "Field type"),
  // A stable machine key, because the label is what a business renames and the
  // key is what stored values are filed under. Renaming a label must not orphan
  // every value already recorded.
  fieldKey: z
    .string()
    .trim()
    .min(1, "A key is required.")
    .max(64)
    .regex(/^[a-z][a-z0-9_]*$/, "A key is lowercase letters, digits and underscores, e.g. shelf_code."),
  options: z.array(z.string().trim().min(1).max(200)).max(100).optional(),
  isRequired: z.boolean().optional(),
  isVisible: z.boolean().optional(),
  sortOrder: z.coerce.number().int().min(0).max(1000).optional(),
};

const createSchema = z
  .object({ entityType: enumSchema(ENTITY_TYPES, "Entity type"), ...baseSchema })
  .refine((value) => !["select", "multiselect"].includes(value.fieldType) || (value.options?.length ?? 0) > 0, {
    message: "A select field needs at least one option.",
    path: ["options"],
  });

const updateSchema = z
  .object({
    label: optionalString(150),
    options: z.array(z.string().trim().min(1).max(200)).max(100).optional(),
    isRequired: z.boolean().optional(),
    isVisible: z.boolean().optional(),
    sortOrder: z.coerce.number().int().min(0).max(1000).optional(),
  })
  .refine((value) => Object.values(value).some((v) => v !== undefined), {
    message: "Provide at least one field to update.",
  });

export const customFieldsRouter = Router();
customFieldsRouter.use(authenticate, requireAccountType("business_user"), auditTrail("settings"));

/**
 * Definitions are readable by anyone who may see the records they describe — a
 * form has to know which fields to draw. Writing them is a settings decision.
 */
customFieldsRouter.get("/", validate(z.object({ entityType: enumSchema(ENTITY_TYPES, "Entity type").optional() }).passthrough(), "query"), async (req, res, next) => {
  try {
    const businessId = tenant(req);
    const { entityType } = req.query;

    const rows = await queryAll(
      `SELECT * FROM custom_field_definitions
        WHERE business_id = ? AND deleted_at IS NULL
          ${entityType ? "AND entity_type = ?" : ""}
        ORDER BY entity_type, sort_order, id`,
      entityType ? [businessId, entityType] : [businessId]
    );
    res.json(ok(rows.map(view)));
  } catch (err) {
    next(err);
  }
});

customFieldsRouter.post("/", authorize("settings.edit"), validate(createSchema), async (req, res, next) => {
  try {
    const businessId = tenant(req);
    const body = req.body;

    const id = await runInTransaction(async (conn) => {
      const [result] = await conn.query(
        `INSERT INTO custom_field_definitions
           (business_id, entity_type, field_key, label, field_type, options,
            is_required, is_visible, sort_order)
         VALUES (?, ?, ?, ?, ?, CAST(? AS JSON), ?, ?, ?)`,
        [
          businessId,
          body.entityType,
          body.fieldKey,
          body.label,
          body.fieldType,
          body.options ? JSON.stringify(body.options) : null,
          body.isRequired ?? false,
          body.isVisible ?? true,
          body.sortOrder ?? 0,
        ]
      );
      return result.insertId;
    });

    const [rows] = await pool.query(`SELECT * FROM custom_field_definitions WHERE id = ?`, [id]);
    res.status(201).json(ok(view(rows[0])));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
});

/**
 * The KEY and the TYPE are not editable.
 *
 * Values are filed under the key and stored as text interpreted by the type, so
 * changing either would silently reinterpret every value already recorded — a
 * date column full of free text, or a field whose stored values belong to a key
 * nothing reads any more. A business that wants a different key or type adds a
 * field and retires this one, which keeps the old values readable.
 */
customFieldsRouter.patch(
  "/:id",
  authorize("settings.edit"),
  validateRequest({ params: idParamsSchema, body: updateSchema }),
  async (req, res, next) => {
    try {
      const businessId = tenant(req);
      const columns = {
        label: "label",
        isRequired: "is_required",
        isVisible: "is_visible",
        sortOrder: "sort_order",
      };

      const sets = [];
      const params = [];
      for (const [key, column] of Object.entries(columns)) {
        if (req.body[key] === undefined) continue;
        sets.push(`${column} = ?`);
        params.push(req.body[key]);
      }
      if (req.body.options !== undefined) {
        sets.push("options = CAST(? AS JSON)");
        params.push(JSON.stringify(req.body.options));
      }

      const affected = await runInTransaction(async (conn) => {
        const [result] = await conn.query(
          `UPDATE custom_field_definitions SET ${sets.join(", ")}, updated_at = NOW()
            WHERE id = ? AND business_id = ? AND deleted_at IS NULL`,
          [...params, req.params.id, businessId]
        );
        return result.affectedRows;
      });
      if (affected === 0) throw errors.notFound("custom field");

      const [rows] = await pool.query(`SELECT * FROM custom_field_definitions WHERE id = ?`, [req.params.id]);
      res.json(ok(view(rows[0])));
    } catch (err) {
      next(toAppError(err) ?? err);
    }
  }
);

/**
 * §45: archived, and the VALUES are kept.
 *
 * A business that stops collecting a field has not decided that what it already
 * collected never happened. The definition is hidden; the values stay attached
 * to their records, which is what makes retiring a field safe.
 */
customFieldsRouter.delete(
  "/:id",
  authorize("settings.edit"),
  validate(idParamsSchema, "params"),
  async (req, res, next) => {
    try {
      const businessId = tenant(req);
      const affected = await runInTransaction(async (conn) => {
        const [result] = await conn.query(
          `UPDATE custom_field_definitions SET deleted_at = NOW(), is_visible = FALSE, updated_at = NOW()
            WHERE id = ? AND business_id = ? AND deleted_at IS NULL`,
          [req.params.id, businessId]
        );
        return result.affectedRows;
      });
      if (affected === 0) throw errors.notFound("custom field");

      const [[values]] = await pool.query(
        `SELECT COUNT(*) AS n FROM custom_field_values WHERE business_id = ? AND definition_id = ?`,
        [businessId, req.params.id]
      );
      res.json(ok({ id: Number(req.params.id), deleted: true, valuesKept: Number(values.n) }));
    } catch (err) {
      next(toAppError(err) ?? err);
    }
  }
);

const constraintMessages = {
  uq_custom_fields_key: "A field with that key already exists for this record type.",
};

/**
 * The values for one record, read and written together (§51).
 *
 * Mounted per entity type so the caller says what it is describing, and a value
 * can never be filed against a definition meant for a different kind of record.
 */
export function customFieldValuesRouter({ entityType, permission, existsIn }) {
  const router = Router();
  router.use(authenticate, requireAccountType("business_user"), auditTrail("settings"));

  router.get(
    "/:id/custom-fields",
    authorize(`${permission}.view`),
    validate(idParamsSchema, "params"),
    async (req, res, next) => {
      try {
        const businessId = tenant(req);
        if (!(await existsIn({ businessId, id: req.params.id }))) throw errors.notFound(entityType);

        const rows = await queryAll(
          `SELECT d.id AS definition_id, d.field_key, d.label, d.field_type, d.options,
                  d.is_required, d.sort_order, v.value
             FROM custom_field_definitions d
             LEFT JOIN custom_field_values v
               ON v.definition_id = d.id AND v.entity_id = ? AND v.business_id = d.business_id
            WHERE d.business_id = ? AND d.entity_type = ? AND d.deleted_at IS NULL
            ORDER BY d.sort_order, d.id`,
          [req.params.id, businessId, entityType]
        );

        res.json(
          ok(
            rows.map((row) => ({
              definitionId: row.definition_id,
              fieldKey: row.field_key,
              label: row.label,
              fieldType: row.field_type,
              options: parseOptions(row.options),
              isRequired: Boolean(row.is_required),
              value: row.value,
            }))
          )
        );
      } catch (err) {
        next(err);
      }
    }
  );

  router.put(
    "/:id/custom-fields",
    authorize(`${permission}.edit`),
    validateRequest({
      params: idParamsSchema,
      // A map of key → value, where null clears one. Values are stored as text
      // because §51 lets a business define any of six types and one column has
      // to hold all of them; the definition says how to read it back.
      body: z.object({ values: z.record(z.string().max(64), z.union([z.string().max(5000), z.number(), z.boolean(), z.null()])) }),
    }),
    async (req, res, next) => {
      try {
        const businessId = tenant(req);
        if (!(await existsIn({ businessId, id: req.params.id }))) throw errors.notFound(entityType);

        const definitions = await queryAll(
          `SELECT id, field_key, is_required FROM custom_field_definitions
            WHERE business_id = ? AND entity_type = ? AND deleted_at IS NULL`,
          [businessId, entityType]
        );
        const byKey = new Map(definitions.map((d) => [d.field_key, d]));

        const unknown = Object.keys(req.body.values).filter((key) => !byKey.has(key));
        if (unknown.length) {
          throw errors.validation(`No such custom field: ${unknown.join(", ")}.`);
        }

        await runInTransaction(async (conn) => {
          for (const [key, raw] of Object.entries(req.body.values)) {
            const definition = byKey.get(key);
            const value = raw === null || raw === "" ? null : String(raw);

            if (value === null && definition.is_required) {
              throw errors.validation(`${key} is required.`);
            }

            if (value === null) {
              await conn.query(
                `DELETE FROM custom_field_values WHERE business_id = ? AND definition_id = ? AND entity_id = ?`,
                [businessId, definition.id, req.params.id]
              );
              continue;
            }

            await conn.query(
              `INSERT INTO custom_field_values (business_id, definition_id, entity_id, value)
               VALUES (?, ?, ?, ?)
               ON DUPLICATE KEY UPDATE value = VALUES(value), updated_at = NOW()`,
              [businessId, definition.id, req.params.id, value]
            );
          }
        });

        const rows = await queryAll(
          `SELECT d.field_key, v.value
             FROM custom_field_definitions d
             LEFT JOIN custom_field_values v
               ON v.definition_id = d.id AND v.entity_id = ? AND v.business_id = d.business_id
            WHERE d.business_id = ? AND d.entity_type = ? AND d.deleted_at IS NULL
            ORDER BY d.sort_order, d.id`,
          [req.params.id, businessId, entityType]
        );

        res.json(ok(Object.fromEntries(rows.map((row) => [row.field_key, row.value]))));
      } catch (err) {
        next(toAppError(err) ?? err);
      }
    }
  );

  return router;
}
