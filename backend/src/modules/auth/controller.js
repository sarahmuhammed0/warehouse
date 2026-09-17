// Thin HTTP glue — parses the request, calls authService with the right
// adapter, shapes the response. No business logic lives here (architecture
// §4's module convention).

import * as authService from "./authService.js";
import { ok } from "../../utils/responseEnvelope.js";
import { getClientIp } from "../../utils/requestInfo.js";

/** @param {import('./accountAdapters.js').businessUserAdapter} adapter */
export function makeAuthController(adapter) {
  return {
    async login(req, res, next) {
      try {
        const { phone, password } = req.body;
        const result = await authService.login(adapter, {
          phone,
          password,
          ip: getClientIp(req),
          userAgent: req.headers["user-agent"] ?? null,
        });
        res.json(
          ok({
            accessToken: result.accessToken,
            refreshToken: result.refreshToken,
            account: result.account,
            business: result.business,
          })
        );
      } catch (err) {
        next(err);
      }
    },

    async refresh(req, res, next) {
      try {
        const { refreshToken } = req.body;
        const result = await authService.refresh(adapter, {
          rawToken: refreshToken,
          ip: getClientIp(req),
          userAgent: req.headers["user-agent"] ?? null,
        });
        res.json(ok(result));
      } catch (err) {
        next(err);
      }
    },

    async logout(req, res, next) {
      try {
        await authService.logout(adapter, req.body?.refreshToken);
        res.json(ok({ loggedOut: true }));
      } catch (err) {
        next(err);
      }
    },

    async me(req, res, next) {
      try {
        const result = await authService.me(adapter, req.auth.userId);
        res.json(ok(result));
      } catch (err) {
        next(err);
      }
    },

    async changePassword(req, res, next) {
      try {
        await authService.changePassword(adapter, req.auth.userId, req.body, getClientIp(req));
        res.json(ok({ changed: true }));
      } catch (err) {
        next(err);
      }
    },
  };
}
