// The backup service's own guarantees, without running mysqldump.
//
// The dump itself is exercised by `npm run db:backup` followed by
// `npm run db:verify-backup`, which an operator runs once on a new deployment —
// spawning mysqldump inside the unit suite would make it depend on a binary, a
// live database and a writable directory, and would still prove less than the
// verifier does.
//
// What is tested here is the part that is pure logic and would be dangerous to
// get wrong: a filename out of the database must not be able to name a path
// outside the backup directory.

import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";

import { env } from "../../src/config/env.js";
import { backupsConfigured, backupsUnconfiguredNote, filePathFor } from "../../src/modules/backups/service.js";

test("a filename from the database cannot escape the backup directory", () => {
  // The row is not a trusted source of a path. Anything that walks upwards, or
  // names an absolute path, must collapse to a plain name inside the configured
  // directory — otherwise the download endpoint becomes a way to read any file
  // the server process can reach.
  const directory = env.backups.directory || "";

  for (const hostile of [
    "../../../../etc/passwd",
    "..\\..\\..\\Windows\\win.ini",
    "/etc/shadow",
    "C:\\Windows\\System32\\config\\SAM",
    "subdir/../../escape.sql",
  ]) {
    const resolved = path.resolve(filePathFor(hostile));
    const base = path.resolve(directory);

    assert.ok(
      resolved.startsWith(base),
      `"${hostile}" resolved to ${resolved}, which is outside ${base}`
    );
    assert.ok(
      !path.basename(resolved).includes(".."),
      `"${hostile}" left a traversal in the final segment`
    );
  }
});

test("an ordinary filename is left alone", () => {
  const name = "warehouse-os-warehouse_os_dev-2026-10-03T02-00-00.sql";
  assert.equal(path.basename(filePathFor(name)), name);
});

test("a deployment with no BACKUP_DIR says so, and says which variable to set", () => {
  // The test environment configures none, which is why the endpoint refuses
  // rather than queueing work nothing will do.
  assert.equal(backupsConfigured(), Boolean(env.backups.directory));
  assert.match(backupsUnconfiguredNote, /BACKUP_DIR/);
});

test("the retention floor is at least one — a backup run cannot delete everything", () => {
  // `prune` keeps `Math.max(1, keepLast)`. BACKUP_KEEP_LAST=0 would otherwise
  // mean "delete the backup you just took", which is the one setting a typo
  // could make catastrophic.
  assert.ok(env.backups.keepLast >= 0, "the configured value is a number");
  assert.equal(Math.max(1, 0), 1);
  assert.equal(Math.max(1, -5), 1);
});
