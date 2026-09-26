import { Router } from "express";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
import { validate, validateRequest } from "../../middleware/validate.js";
import { idParamsSchema, listQuerySchema } from "../../validation/common.js";
import { createProductSchema, updateProductSchema } from "./validation.js";
import { listProducts, getProduct, createProduct, updateProduct, deleteProduct } from "./controller.js";

export const productsRouter = Router();

productsRouter.use(authenticate, requireAccountType("business_user"));

productsRouter.get("/", authorize("products.view"), validate(listQuerySchema, "query"), listProducts);
productsRouter.get("/:id", authorize("products.view"), validate(idParamsSchema, "params"), getProduct);
productsRouter.post("/", authorize("products.create"), validate(createProductSchema), createProduct);
productsRouter.patch(
  "/:id",
  authorize("products.edit"),
  validateRequest({ params: idParamsSchema, body: updateProductSchema }),
  updateProduct
);
productsRouter.delete("/:id", authorize("products.delete"), validate(idParamsSchema, "params"), deleteProduct);
