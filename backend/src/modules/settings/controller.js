import { ok } from "../../utils/responseEnvelope.js";
import { runInTransaction } from "../../db/pool.js";
import { SETTINGS, withDefaults } from "./catalog.js";
import { readSettings, writeSetting } from "./repository.js";

const tenant = (req) => req.auth.businessId;

/**
 * Every setting, with its default where nothing has been stored — so the
 * client never has to know which keys happen to have rows yet.
 */
export async function getSettings(req, res, next) {
  try {
    const values = withDefaults(await readSettings(tenant(req)));
    res.json(
      ok({
        values,
        // The metadata travels with the values so the UI can label and type a
        // setting without hard-coding a second copy of this catalogue.
        definitions: Object.fromEntries(
          Object.entries(SETTINGS).map(([key, spec]) => [
            key,
            { type: spec.type, default: spec.default, description: spec.description },
          ])
        ),
      })
    );
  } catch (err) {
    next(err);
  }
}

/** A partial update: only the keys present in the body are written. */
export async function updateSettings(req, res, next) {
  try {
    const businessId = tenant(req);
    const entries = Object.entries(req.body);

    // One transaction for the whole patch: a client turning two related
    // settings on together should not end up with one of them applied.
    await runInTransaction(async (conn) => {
      for (const [key, value] of entries) {
        await writeSetting({ businessId, key, value, conn });
      }
    });

    res.json(ok({ values: withDefaults(await readSettings(businessId)) }));
  } catch (err) {
    next(err);
  }
}
