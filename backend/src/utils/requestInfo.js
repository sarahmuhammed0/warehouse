// IP extraction for audit logs and login-attempt tracking (§26).
//
// The address this returns is what §7's lockout is counted against and what every
// audit row records, so being wrong about it has two distinct failure modes:
//
//   Behind a proxy, reading the TCP peer gives nginx's address for every
//   request. The lockout then becomes global — one attacker's five bad
//   passwords lock out every user in the system — and the trail attributes
//   every action to the proxy.
//
//   Reading X-Forwarded-For when nothing trustworthy sets it lets a client
//   claim any address it likes, so an attacker never accumulates failures
//   against a single IP and is never locked out at all.
//
// Neither is a safe default to guess, so the deployment states it:
// `TRUST_PROXY_HOPS` is the exact number of proxies in front of this server
// (`app.js` passes it to Express). When it is 0 — direct exposure, and local
// development — the TCP peer is the only honest answer. When it is set, Express
// has already walked that many hops from the right-hand end of the header, and
// `req.ip` is the client.
import { env } from "../config/env.js";

export function getClientIp(req) {
  if (env.server.trustProxyHops > 0) {
    // `req.ip` with `trust proxy` set to a hop COUNT: Express skips exactly that
    // many trusted entries from the end, so a forged prefix cannot reach it.
    return req.ip ?? req.socket?.remoteAddress ?? null;
  }
  return req.socket?.remoteAddress ?? null;
}
