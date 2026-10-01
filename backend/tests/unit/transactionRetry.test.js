// The deadlock retry (`withLockRetry`).
//
// InnoDB picks a victim when two transactions deadlock and rolls it back whole;
// MySQL's manual is explicit that an application must be ready to re-issue such
// a transaction. This is that readiness, and it is tested here rather than by
// provoking a real deadlock — which is exactly the kind of code that otherwise
// ships unexercised and turns out to be wrong on the night it matters.

import { test } from "node:test";
import assert from "node:assert/strict";

import { withLockRetry, isRetryableLockError, MAX_TRANSACTION_ATTEMPTS } from "../../src/db/pool.js";

/** A rolled-back lock failure, as mysql2 reports one. */
function lockError(code) {
  const error = new Error(code);
  error.code = code;
  return error;
}

// Every retry in these tests is instant — the real backoff exists to break up a
// colliding interleaving, which no fake runner has.
const instant = { backoffMs: () => 0 };

test("a deadlock victim is retried and its result returned", async () => {
  let calls = 0;
  const result = await withLockRetry(async () => {
    calls += 1;
    if (calls === 1) throw lockError("ER_LOCK_DEADLOCK");
    return "committed";
  }, instant);

  assert.equal(result, "committed");
  assert.equal(calls, 2, "the second attempt is the one that succeeded");
});

test("a lock-wait timeout is retried too — nothing was applied either", async () => {
  let calls = 0;
  await withLockRetry(async () => {
    calls += 1;
    if (calls < 3) throw lockError("ER_LOCK_WAIT_TIMEOUT");
    return true;
  }, instant);

  assert.equal(calls, 3);
});

test("retries are bounded, and the original error is what escapes", async () => {
  let calls = 0;
  await assert.rejects(
    () =>
      withLockRetry(async () => {
        calls += 1;
        throw lockError("ER_LOCK_DEADLOCK");
      }, instant),
    (error) => {
      // The caller sees the database's own error, which `toAppError` maps to a
      // 409. Swallowing it and returning a value would report a write that
      // never happened.
      assert.equal(error.code, "ER_LOCK_DEADLOCK");
      return true;
    }
  );

  assert.equal(calls, MAX_TRANSACTION_ATTEMPTS, "bounded — it must not retry forever");
});

test("any other failure is not retried, because it would not succeed twice", async () => {
  let calls = 0;
  await assert.rejects(
    () =>
      withLockRetry(async () => {
        calls += 1;
        throw lockError("ER_DUP_ENTRY");
      }, instant),
    { code: "ER_DUP_ENTRY" }
  );

  // A duplicate key, a validation failure, a constraint violation: all of them
  // fail identically on a second attempt. Retrying them would turn one honest
  // error into three and delay it.
  assert.equal(calls, 1);
});

test("a successful transaction runs exactly once", async () => {
  let calls = 0;
  const result = await withLockRetry(async () => {
    calls += 1;
    return 42;
  }, instant);

  assert.equal(result, 42);
  assert.equal(calls, 1, "no speculative re-run on the happy path");
});

test("only the two rolled-back lock failures count as retryable", () => {
  assert.ok(isRetryableLockError(lockError("ER_LOCK_DEADLOCK")));
  assert.ok(isRetryableLockError(lockError("ER_LOCK_WAIT_TIMEOUT")));

  for (const code of ["ER_DUP_ENTRY", "ER_NO_REFERENCED_ROW_2", "ECONNRESET", undefined]) {
    assert.ok(!isRetryableLockError(lockError(code)), `${code} must not be retried`);
  }
  assert.ok(!isRetryableLockError(undefined));
  assert.ok(!isRetryableLockError(new Error("no code at all")));
});

test("the backoff grows, so a retry does not reproduce the same collision", async () => {
  const waits = [];
  let calls = 0;

  await withLockRetry(
    async () => {
      calls += 1;
      if (calls < 3) throw lockError("ER_LOCK_DEADLOCK");
      return true;
    },
    {
      backoffMs: (attempt) => {
        waits.push(attempt);
        return 0;
      },
    }
  );

  assert.deepEqual(waits, [1, 2], "the attempt number is what grows the pause");
});
