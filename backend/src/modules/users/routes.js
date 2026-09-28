import { Router } from "express";
import { z } from "zod";

import { authenticate } from "../../middleware/authenticate.js";
import { requireAccountType } from "../../middleware/requireAccountType.js";
import { authorize } from "../../middleware/authorize.js";
import { auditTrail } from "../../middleware/auditTrail.js";
import { validate, validateRequest } from "../../middleware/validate.js";
import {
  idParamsSchema,
  idSchema,
  listQuerySchema,
  requiredString,
  optionalString,
  enumSchema,
} from "../../validation/common.js";
import { list, get, create, update, remove, resetPassword } from "./controller.js";

/** §23's staff record. `inactive` is the client's word for the schema's `disabled`. */
const statusSchema = enumSchema(["active", "disabled"], "Status");

const createUserSchema = z.object({
  name: requiredString(150, "A name"),
  phone: requiredString(20, "A phone number"),
  email: optionalString(255),
  roleId: idSchema,
  // Optional: left out, the server generates one and returns it once so the
  // owner can pass it on. §3 stores only the hash either way.
  password: z.string().min(8, "A password must be at least 8 characters.").optional(),
  status: statusSchema.optional(),
});

const updateUserSchema = z
  .object({
    name: optionalString(150),
    email: optionalString(255),
    roleId: idSchema.optional(),
    status: statusSchema.optional(),
  })
  .refine((value) => Object.values(value).some((v) => v !== undefined), {
    message: "Provide at least one field to update.",
  });

const resetPasswordSchema = z.object({
  password: z.string().min(8, "A password must be at least 8 characters.").optional(),
});

export const usersRouter = Router();
usersRouter.use(authenticate, requireAccountType("business_user"), auditTrail("users"));

/**
 * Gated on `users.*` — §24's own module, which by default only the owner role
 * holds. Staff management is the one module where a wrong grant compounds: a
 * role that may edit users can grant itself everything else.
 *
 * A user's PHONE is deliberately not editable. It is the credential (§3) and
 * the unique identity across every business, so changing it is closer to
 * creating a different account than to editing this one — and an owner who
 * could rewrite it could point a colleague's login at a number they control.
 */
usersRouter.get("/", authorize("users.view"), validate(listQuerySchema, "query"), list);
usersRouter.get("/:id", authorize("users.view"), validate(idParamsSchema, "params"), get);
usersRouter.post("/", authorize("users.create"), validate(createUserSchema), create);

usersRouter.patch(
  "/:id",
  authorize("users.edit"),
  validateRequest({ params: idParamsSchema, body: updateUserSchema }),
  update
);

usersRouter.post(
  "/:id/password",
  authorize("users.edit"),
  validateRequest({ params: idParamsSchema, body: resetPasswordSchema }),
  resetPassword
);

usersRouter.delete("/:id", authorize("users.delete"), validate(idParamsSchema, "params"), remove);
