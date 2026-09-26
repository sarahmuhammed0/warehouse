import { ok, paginated } from "../../utils/responseEnvelope.js";
import { parsePagination, paginationMeta } from "../../db/pagination.js";
import { errors } from "../../utils/AppError.js";
import { toAppError } from "../../utils/databaseError.js";
import {
  categoriesRepository,
  CATEGORY_JOINS,
  categoryInUse,
  categoryHasChildren,
  wouldCreateCycle,
  categoryOptions,
} from "./repository.js";

function toView(row) {
  return {
    id: row.id,
    name: row.name,
    code: row.code,
    parentId: row.parent_id,
    parentName: row.parent_name ?? null,
    imageUrl: row.image_url,
    description: row.description,
    sortOrder: row.sort_order,
    status: row.status,
    // §7 shows a category's product count; derived, never stored, so it
    // cannot drift from the products themselves.
    productCount: Number(row.product_count ?? 0),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

const constraintMessages = {
  uq_categories_code: "A category with this code already exists.",
};

const tenant = (req) => req.auth.businessId;

/**
 * A parent must exist, belong to this business, and not create a cycle.
 *
 * The first two are what stop a client naming another tenant's category as
 * a parent — the foreign key alone would allow it, because it constrains
 * the id but knows nothing about who owns it (§36).
 */
async function validateParent({ businessId, parentId, categoryId = null }) {
  if (parentId === undefined || parentId === null) return;

  const parent = await categoriesRepository.findById({ businessId, id: parentId });
  if (!parent) throw errors.validation("The parent category does not exist.");

  if (categoryId && (await wouldCreateCycle({ businessId, categoryId, parentId }))) {
    throw errors.validation("A category cannot be placed inside itself or one of its own subcategories.");
  }
}

export async function listCategories(req, res, next) {
  try {
    const pagination = parsePagination(req.query);
    const { rows, total } = await categoriesRepository.list({
      businessId: tenant(req),
      query: req.query,
      pagination,
      joins: CATEGORY_JOINS,
    });
    res.json(paginated(rows.map(toView), paginationMeta(pagination, total)));
  } catch (err) {
    next(err);
  }
}

/** Unpaginated picker list — §7's tree for a product form's dropdown. */
export async function listCategoryOptions(req, res, next) {
  try {
    const rows = await categoryOptions(tenant(req));
    res.json(ok(rows.map((r) => ({ id: r.id, parentId: r.parent_id, name: r.name }))));
  } catch (err) {
    next(err);
  }
}

export async function getCategory(req, res, next) {
  try {
    const row = await categoriesRepository.requireById({
      businessId: tenant(req),
      id: req.params.id,
      joins: CATEGORY_JOINS,
      label: "category",
    });
    res.json(ok(toView(row)));
  } catch (err) {
    next(err);
  }
}

export async function createCategory(req, res, next) {
  try {
    const businessId = tenant(req);
    await validateParent({ businessId, parentId: req.body.parentId });

    const id = await categoriesRepository.create({ businessId, data: req.body });
    const row = await categoriesRepository.findById({ businessId, id, joins: CATEGORY_JOINS });
    res.status(201).json(ok(toView(row)));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
}

export async function updateCategory(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = req.params.id;

    await categoriesRepository.requireById({ businessId, id, label: "category" });
    await validateParent({ businessId, parentId: req.body.parentId, categoryId: id });

    await categoriesRepository.update({ businessId, id, data: req.body });
    const row = await categoriesRepository.findById({ businessId, id, joins: CATEGORY_JOINS });
    res.json(ok(toView(row)));
  } catch (err) {
    next(toAppError(err, { constraintMessages }) ?? err);
  }
}

export async function deleteCategory(req, res, next) {
  try {
    const businessId = tenant(req);
    const id = req.params.id;
    await categoriesRepository.requireById({ businessId, id, label: "category" });

    // §45: archiving must not orphan anything. Both checks exist because a
    // soft delete slips past the foreign keys entirely — the row stays, so
    // RESTRICT never fires, and the products or children would simply point
    // at something invisible.
    if (await categoryHasChildren({ businessId, categoryId: id })) {
      throw errors.conflict("This category still has subcategories. Move or archive those first.");
    }
    if (await categoryInUse({ businessId, categoryId: id })) {
      throw errors.conflict("This category still contains products. Move those products first.");
    }

    await categoriesRepository.softDelete({ businessId, id });
    res.json(ok({ id: Number(id), deleted: true }));
  } catch (err) {
    next(err);
  }
}
