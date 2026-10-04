#!/usr/bin/env node
// Builds the Android app for production, with the defines it cannot be shipped
// without. The counterpart to build-web.mjs, and it exists for the same reason.
//
// `APP_MODE` defaults to `demo`, so a plain `flutter build apk --release`
// produces an installable APK that NEVER CONTACTS THE SERVER and shows invented
// data. On a phone that is worse than on the web: there is no address bar to
// reveal it, the app looks complete, and whatever anyone types into it is gone
// the moment the process dies.
//
// Usage:
//   node scripts/build-apk.mjs --api https://warehouse.example.com/api
//   node scripts/build-apk.mjs --api http://192.168.1.50:4000/api --debug
//   node scripts/build-apk.mjs --api ... --bundle     (an .aab for the Play Store)
//   node scripts/build-apk.mjs --demo                 (a deliberate demo build)

import { spawn } from "node:child_process";
import { readFile, stat } from "node:fs/promises";
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
const debug = args.includes("--debug");
const bundle = args.includes("--bundle");
const apiIndex = args.indexOf("--api");
const apiBaseUrl = apiIndex === -1 ? null : args[apiIndex + 1];

if (!demo && !apiBaseUrl) {
  die(
    "Where is the API? Pass --api <url>.\n" +
      "  Building without it produces a DEMO app that never contacts a server —\n" +
      "  and on a phone there is no address bar to give that away.\n" +
      "  If a demo build is genuinely what you want, pass --demo and say so."
  );
}

if (apiBaseUrl && !/^https?:\/\//.test(apiBaseUrl)) {
  // Unlike the web build, a relative path is never right here: the app is not
  // served from the API's origin, so there is no origin to be relative to.
  die(`--api must be a full URL for a mobile build, not "${apiBaseUrl}".`);
}

if (apiBaseUrl && /^https?:\/\/(localhost|127\.0\.0\.1)/i.test(apiBaseUrl)) {
  die(
    `--api points at ${apiBaseUrl}, which on a phone means THE PHONE ITSELF.\n` +
      "  Use the server's address on the network, e.g. http://192.168.1.50:4000/api."
  );
}

if (apiBaseUrl && apiBaseUrl.startsWith("http://") && !debug) {
  // Not a preference. Android blocks cleartext traffic by default, and the
  // release manifest deliberately does not override it, so this APK would fail
  // every request with nothing on screen to explain why.
  die(
    `--api is plain http, which a RELEASE build cannot use: Android blocks cleartext\n` +
      "  traffic and the release manifest does not override it (deliberately — the app\n" +
      "  carries passwords and tokens).\n" +
      "  Use https for a release build, or add --debug to test against a local server."
  );
}

const defines = demo
  ? ["--dart-define=APP_MODE=demo"]
  : ["--dart-define=APP_MODE=backend", `--dart-define=API_BASE_URL=${apiBaseUrl}`];

const target = bundle ? "appbundle" : "apk";
const mode = debug ? "--debug" : "--release";

say(`${BOLD}Building the Android app${RESET}`);
say(`  target ${target}${bundle ? " (.aab, for the Play Store)" : " (.apk)"}`);
say(`  mode   ${debug ? "debug" : "release"}`);
say(`  app    ${demo ? "DEMO (local data, no server)" : "backend"}`);
if (!demo) say(`  api    ${apiBaseUrl}`);
say();

const exitCode = await new Promise((resolve) => {
  const child = spawn("flutter", ["build", target, mode, ...defines], {
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

const artefact = bundle
  ? path.join(frontend, "build", "app", "outputs", "bundle", debug ? "debug" : "release", debug ? "app-debug.aab" : "app-release.aab")
  : path.join(frontend, "build", "app", "outputs", "flutter-apk", debug ? "app-debug.apk" : "app-release.apk");

let size;
try {
  size = (await stat(artefact)).size;
} catch {
  die(`The build reported success but ${artefact} is not there.`);
}

// Read the artefact back and look for the URL, the same proof build-web.mjs
// gives. A release build compiles Dart to a native library that still carries
// its string constants, so the define is findable; a DEBUG build keeps its code
// in a compressed kernel blob where it is not, so that check is release-only and
// says so rather than pretending to have verified something.
if (!demo && !debug) {
  const contents = await readFile(artefact, "latin1");
  if (!contents.includes(apiBaseUrl)) {
    die(
      `The build does not contain "${apiBaseUrl}", so API_BASE_URL did not reach the\n` +
        "  compiler. Refusing to leave an artefact that would fall back to demo data."
    );
  }
  say();
  say(`${GREEN}✓ Built in backend mode against ${apiBaseUrl}, and verified in the artefact${RESET}`);
} else if (demo) {
  say();
  say(`${GREEN}✓ Built in demo mode, as asked.${RESET}`);
  say(`${YELLOW}  This app shows local sample data and never contacts a server.${RESET}`);
} else {
  say();
  say(`${GREEN}✓ Built in backend mode against ${apiBaseUrl}${RESET}`);
  say(`${YELLOW}  A debug build's code is compressed, so the define could not be verified${RESET}`);
  say(`${YELLOW}  by reading the file back. Release builds are checked.${RESET}`);
}

say(`  ${artefact}  (${(size / 1048576).toFixed(1)} MB)`);

if (!debug && !demo) {
  say();
  say(`${YELLOW}Check the signing line above: without android/key.properties this is signed${RESET}`);
  say(`${YELLOW}with the DEBUG key and cannot be published. See docs/deployment.md §9.${RESET}`);
}
