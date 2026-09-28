// API routing foundation. Every module adds one line here when it's built —
// this file never grows business logic itself, only mounts.

import { Router } from "express";
import { healthRouter } from "./health.routes.js";
import { authRouter } from "../modules/auth/routes.js";
import { adminAuthRouter } from "../modules/admin-auth/routes.js";
import { businessesRouter, registrationRouter } from "../modules/businesses/routes.js";
import { unitsRouter } from "../modules/units/routes.js";
import { categoriesRouter } from "../modules/categories/routes.js";
import { warehousesRouter, storageLocationsRouter } from "../modules/locations/routes.js";
import { productsRouter } from "../modules/products/routes.js";
import { inventoryRouter } from "../modules/inventory/routes.js";
import { customersRouter, suppliersRouter } from "../modules/parties/routes.js";
import { ordersRouter } from "../modules/orders/routes.js";
import { purchasesRouter } from "../modules/purchases/routes.js";
import { returnsRouter, orderReturnableRouter } from "../modules/returns/routes.js";
import { productionRouter, productBomRouter } from "../modules/production/routes.js";
import { variantsRouter } from "../modules/variants/routes.js";
import { transfersRouter } from "../modules/transfers/routes.js";
import { reportsRouter } from "../modules/reports/routes.js";
import { notificationsRouter } from "../modules/notifications/routes.js";
import { usersRouter } from "../modules/users/routes.js";
import { rolesRouter } from "../modules/roles/routes.js";
import { auditRouter } from "../modules/audit/routes.js";
import { settingsRouter } from "../modules/settings/routes.js";
import { businessProfileRouter, numberingRouter } from "../modules/settings/profileRoutes.js";

export const apiRouter = Router();

apiRouter.use("/health", healthRouter);
apiRouter.use("/auth", authRouter); // business users
apiRouter.use("/admin/auth", adminAuthRouter); // System Admins — separate router, separate identity table
apiRouter.use("/admin/businesses", businessesRouter); // System-Admin-only (see modules/businesses)
apiRouter.use("/registration", registrationRouter); // PUBLIC: business self-registration, creates a pending business

// ---- Business modules (tenant-scoped, permission-checked) ----
apiRouter.use("/units", unitsRouter);
apiRouter.use("/categories", categoriesRouter);
apiRouter.use("/warehouses", warehousesRouter);
apiRouter.use("/storage-locations", storageLocationsRouter);
apiRouter.use("/products", productsRouter);
apiRouter.use("/inventory", inventoryRouter);
apiRouter.use("/customers", customersRouter);
apiRouter.use("/suppliers", suppliersRouter);
apiRouter.use("/orders", ordersRouter);
apiRouter.use("/purchases", purchasesRouter);
apiRouter.use("/returns", returnsRouter);
apiRouter.use("/production-orders", productionRouter);
// §21's recipe belongs to the product, so it is addressed as one of its
// sub-resources; falls through from productsRouter, which has no /:id/bom.
apiRouter.use("/products", productBomRouter);
// Falls through from ordersRouter, which has no /:id/returnable of its own.
apiRouter.use("/orders", orderReturnableRouter);
apiRouter.use("/stock-transfers", transfersRouter);
// §9 hangs off the product, like §21 does; falls through from productsRouter.
apiRouter.use("/products", variantsRouter);
apiRouter.use("/reports", reportsRouter);
apiRouter.use("/notifications", notificationsRouter);
apiRouter.use("/users", usersRouter);
apiRouter.use("/roles", rolesRouter);
apiRouter.use("/audit-logs", auditRouter);
apiRouter.use("/settings", settingsRouter);
// §34s Business Information, and §29s numbering — the Settings sections that
// are columns and rows rather than key/value.
apiRouter.use("/business", businessProfileRouter);
apiRouter.use("/documents", numberingRouter);
