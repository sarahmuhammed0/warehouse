#!/usr/bin/env node
// Builds the Flutter web app for production, with the defines it cannot be
// shipped without.
//
// This script exists because of one specific, silent failure: `APP_MODE` defaults
// to `demo`, so a plain `flutter build web --release` produces a complete,
// working, deployable bundle that NEVER CONTACTS THE SERVER and shows invented
// data. Nothing about it looks wrong — the login screen accepts the demo
// identities, the dashboard has numbers on it — and a business could use it for a
// day before noticing that nothing they entered was saved.
//
// So the mode is not a flag someone remembers. It is the default here, and the
// build refuses rather than guessing when it has not been told where the API is.
//
// Usage:
//   node scripts/build-web.mjs --api https://warehouse.example.com/api
//   node scripts/build-web.mjs --api /api            (same origin as the app)
//   node scripts/build-web.mjs --demo                (a deliberate demo build)

import { spawn } from "node:child_process";
import { rm, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const frontend = path.join(root, "frontend");

const RESET = "\u001b[0m";
const BOLD = "\u001b[1m";
const RED = "\u001b[31m";
const GREEN = "\u001b[32m";
const YELLOW = "\u001b[33m";

const say = (m = "") => console.log(m); // eslint-disable-line no-console
const die = (m) => {
  console.error(`${RED}✗ ${m}${RESET}`); // eslint-disable-line no-console
  process.exit(1);
};

const args = process.argv.slice(2);
const demo = args.includes("--demo");
const apiIndex = args.indexOf("--api");
const apiBaseUrl = apiIndex === -1 ? null : args[apiIndex + 1];

if (!demo && !apiBaseUrl) {
  die(
    "Where is the API? Pass --api <url>, e.g. --api /api for the same origin.\n" +
      "  Building without it would produce a DEMO bundle that never contacts a server.\n" +
      "  If that is genuinely what you want, pass --demo and say so."
  );
}

if (apiBaseUrl && !/^(https?:\/\/|\/)/.test(apiBaseUrl)) {
  die(`--api must be a URL or an absolute path, not "${apiBaseUrl}".`);
}

if (apiBaseUrl && apiBaseUrl.startsWith("http://") && !apiBaseUrl.startsWith("http://localhost")) {
  // Not fatal — someone may be terminating TLS elsewhere — but every token this
  // app holds crosses that connection.
  say(`${YELLOW}⚠ --api is plain http. Access tokens and passwords would travel unencrypted.${RESET}`);
  say();
}

const defines = demo
  ? ["--dart-define=APP_MODE=demo"]
  : ["--dart-define=APP_MODE=backend", `--dart-define=API_BASE_URL=${apiBaseUrl}`];

say(`${BOLD}Building the web app${RESET}`);
say(`  mode   ${demo ? "DEMO (local data, no server)" : "backend"}`);
if (!demo) say(`  api    ${apiBaseUrl}`);
say();

// The output directory is removed first. Flutter does not clear it, so a file
// that existed in the previous build and not in this one would stay and be
// served — including, in the worst case, a stale main.dart.js from a demo build.
await rm(path.join(frontend, "build", "web"), { recursive: true, force: true });

const exitCode = await new Promise((resolve) => {
  const child = spawn("flutter", ["build", "web", "--release", ...defines], {
    cwd: frontend,
    stdio: "inherit",
    shell: process.platform === "win32",
  });
  child.on("error", (error) =>
    die(error.code === "ENOENT" ? "flutter was not found on PATH." : error.message)
  );
  child.on("close", resolve);
});

if (exitCode !== 0) die(`flutter build failed (exit ${exitCode}).`);

// Proof, not assumption: the compiled bundle is read back and checked for the
// mode it was built with. A define that failed to reach the compiler would
// otherwise leave a demo build sitting in build/web looking finished.
const bundle = path.join(frontend, "build", "web", "main.dart.js");
let contents;
try {
  contents = await readFile(bundle, "utf8");
} catch {
  die(`The build reported success but ${bundle} is not there.`);
}

if (!demo) {
  if (!contents.includes(apiBaseUrl)) {
    die(
      `The bundle does not contain "${apiBaseUrl}", so API_BASE_URL did not reach the compiler.\n` +
        "  Refusing to leave a build that would fall back to demo data."
    );
  }
  say();
  say(`${GREEN}✓ Built in backend mode against ${apiBaseUrl}${RESET}`);
} else {
  say();
  say(`${GREEN}✓ Built in demo mode, as asked.${RESET}`);
  say(`${YELLOW}  This bundle shows local sample data and never contacts a server.${RESET}`);
}

say(`  ${path.join(frontend, "build", "web")}`);
