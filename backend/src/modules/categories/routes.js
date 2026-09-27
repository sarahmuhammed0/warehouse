import { Router } from "express";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
import { auditTrail } from "../../middleware/auditTrail.js";
import { validate, validateRequest } from "../../middleware/validate.js";
import { idParamsSchema, listQuerySchema } from "../../validation/common.js";
import { createCategorySchema, updateCategorySchema } from "./validation.js";
import {
  listCategories,
  listCategoryOptions,
  getCategory,
  createCategory,
  updateCategory,
  deleteCategory,
} from "./controller.js";

export const categoriesRouter = Router();

categoriesRouter.use(authenticate, requireAccountType("business_user"), auditTrail("categories"));

categoriesRouter.get("/", authorize("categories.view"), validate(listQuerySchema, "query"), listCategories);

// Declared before "/:id", or "options" is matched as a category id.
categoriesRouter.get("/options", authorize("categories.view"), listCategoryOptions);

categoriesRouter.get("/:id", authorize("categories.view"), validate(idParamsSchema, "params"), getCategory);

categoriesRouter.post("/", authorize("categories.create"), validate(createCategorySchema), createCategory);

categoriesRouter.patch(
  "/:id",
  authorize("categories.edit"),
  validateRequest({ params: idParamsSchema, body: updateCategorySchema }),
  updateCategory
);

categoriesRouter.delete(
  "/:id",
  authorize("categories.delete"),
  validate(idParamsSchema, "params"),
  deleteCategory
);
