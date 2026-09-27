import { Router } from "express";
import { z } from "zod";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
import { auditTrail } from "../../middleware/auditTrail.js";
import { validate, validateRequest } from "../../middleware/validate.js";
import {
  idParamsSchema,
  listQuerySchema,
  requiredString,
  optionalString,
  enumSchema,
} from "../../validation/common.js";
import { customersController, suppliersController } from "./controller.js";

const statusSchema = enumSchema(["active", "inactive"], "Status");

/**
 * §18: phone is optional and NOT unique. A walk-in cash customer has no
 * phone at all, and two family members may share one — making it required
 * or unique would block real sales.
 */
const partyFields = {
  code: optionalString(50),
  phone: optionalString(20),
  phoneSecondary: optionalString(20),
  email: optionalString(255),
  address: optionalString(255),
  notes: optionalString(5000),
  status: statusSchema.optional(),
};

const createCustomerSchema = z.object({
  name: requiredString(200),
  company: optionalString(200),
  ...partyFields,
});

const updateCustomerSchema = z
  .object({ name: optionalString(200), company: optionalString(200), ...partyFields })
  .refine((v) => Object.values(v).some((x) => x !== undefined), {
    message: "Provide at least one field to update.",
  });

const createSupplierSchema = z.object({
  name: requiredString(200),
  company: optionalString(200),
  contactPerson: optionalString(150),
  ...partyFields,
});

const updateSupplierSchema = z
  .object({
    name: optionalString(200),
    company: optionalString(200),
    contactPerson: optionalString(150),
    ...partyFields,
  })
  .refine((v) => Object.values(v).some((x) => x !== undefined), {
    message: "Provide at least one field to update.",
  });

/** Both routers are identical apart from the module they are gated on. */
function partyRouter({ controller, module, createSchema, updateSchema }) {
  const router = Router();
  router.use(authenticate, requireAccountType("business_user"), auditTrail(module));

  router.get("/", authorize(`${module}.view`), validate(listQuerySchema, "query"), controller.list);
  router.get("/:id", authorize(`${module}.view`), validate(idParamsSchema, "params"), controller.get);
  router.post("/", authorize(`${module}.create`), validate(createSchema), controller.create);
  router.patch(
    "/:id",
    authorize(`${module}.edit`),
    validateRequest({ params: idParamsSchema, body: updateSchema }),
    controller.update
  );
  router.delete("/:id", authorize(`${module}.delete`), validate(idParamsSchema, "params"), controller.remove);
  return router;
}

export const customersRouter = partyRouter({
  controller: customersController,
  module: "customers",
  createSchema: createCustomerSchema,
  updateSchema: updateCustomerSchema,
});

export const suppliersRouter = partyRouter({
  controller: suppliersController,
  module: "suppliers",
  createSchema: createSupplierSchema,
  updateSchema: updateSupplierSchema,
});
