// The one shared response shape every endpoint returns (architecture §29),
// so the frontend's http client (services/httpClient.js) only ever has to
// unwrap one envelope, no matter which module the data came from.

export function ok(data, meta) {
  const body = { success: true, data };
  if (meta) body.meta = meta;
  return body;
}

export function fail(code, message) {
  return { success: false, error: { code, message } };
}
