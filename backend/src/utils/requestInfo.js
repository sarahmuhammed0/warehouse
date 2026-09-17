// IP extraction for audit logs / login-attempt tracking (Phase 2 §26).
//
// DECISION: uses `req.socket.remoteAddress` (the raw TCP peer address),
// NOT `req.ip` / `X-Forwarded-For`. Express's `req.ip` only reflects a
// proxy header when `app.set('trust proxy', ...)` is configured — and
// this app does NOT enable that (see app.js), because doing so safely
// requires knowing exactly how many trusted reverse-proxy hops sit in
// front of the server in each deployment. Blindly trusting
// `X-Forwarded-For` when there is no such proxy (true for local dev, and
// for a deployment fronted directly) would let any client simply claim to
// be a different IP, defeating the very lockout/audit purpose this value
// is collected for. When this app is deployed behind a real reverse proxy
// (nginx, a load balancer), `trust proxy` must be set to that proxy's
// exact hop count/IP range and this function updated to read `req.ip` —
// documented here so that's a deliberate deployment-time decision, not
// silently different between environments.
export function getClientIp(req) {
  return req.socket?.remoteAddress ?? null;
}
