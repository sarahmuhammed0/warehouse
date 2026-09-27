// §30's activity log, for every module that changes data.
//
// WHY THIS IS MIDDLEWARE AND NOT A CALL IN EACH CONTROLLER: §30 asks for a
// trail of who did what and when, across the whole system. Written by hand in
// each controller, it is a line someone forgets — and an audit trail with
// holes is worse than none, because the holes are invisible. Mounted once per
// router, it covers every current and future endpoint on that router by
// construction.
//
// WHAT IT DELIBERATELY DOES NOT DO: it is not part of the request's
// transaction. The row is written after the response has been sent, so a slow
// or failing audit insert can never turn a successful save into an error for
// the user. The trade is that a database failure in the window between commit
// and audit loses that one entry; it is logged at error level when that
// happens. Where an event must be inseparable from the change itself — §15's
// order edit trail, §17's cancellation — the module writes its own row inside
// the transaction, and does not rely on this.

import { writeAuditLog } from "../modules/auth/repository.js";
import { getClientIp } from "../utils/requestInfo.js";
import { logger } from "../utils/logger.js";

/**
 * A read is not an audit event, so only these methods are recorded. Anything
 * not listed here passes straight through.
 */
const ACTIONS = { POST: "create", PATCH: "update", PUT: "update", DELETE: "delete" };

/**
 * @param {string} module one of §24's module names, e.g. "products". Written
 *   to `audit_logs.module`, which §30 requires for filtering.
 */
export function auditTrail(module) {
  return function auditTrailMiddleware(req, res, next) {
    const action = ACTIONS[req.method];
    if (!action) return next();

    // The created row's id is only in the response body, so the body is
    // captured on its way out. `res.json` is what every controller here uses.
    let body;
    const sendJson = res.json.bind(res);
    res.json = (payload) => {
      body = payload;
      return sendJson(payload);
    };

    // "finish" fires once the response is fully flushed to the client — the
    // point after which nothing this middleware does can affect it.
    res.on("finish", () => {
      // A 4xx/5xx changed nothing, so there is nothing to record. A failed
      // *login* is worth recording and is, by authService — that is a
      // security event, not a data change.
      if (res.statusCode >= 400) return;

      const auth = req.auth ?? {};
      const referenceId = body?.data?.id ?? req.params?.id ?? null;

      writeAuditLog({
        businessId: auth.businessId ?? null,
        // "system" covers an unauthenticated route; `actor_id` stays null,
        // which is what the column is nullable for.
        actorType: auth.accountType ?? "system",
        actorId: auth.userId ?? null,
        module,
        action: `${module}.${action}`,
        description: `${action} on ${module}${referenceId ? ` #${referenceId}` : ""}`,
        ip: getClientIp(req),
        referenceType: module,
        referenceId: referenceId === null ? null : Number(referenceId) || null,
      }).catch((error) => {
        // Deliberately swallowed: the user's change already succeeded and
        // was already reported. Losing the audit row is worth knowing about,
        // not worth a 500 on work that is done.
        logger.error({ err: error, module, action }, "Failed to write an audit log entry");
      });
    });

    next();
  };
}
