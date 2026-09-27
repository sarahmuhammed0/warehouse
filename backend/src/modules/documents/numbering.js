import { errors } from "../../utils/AppError.js";

/**
 * Document numbers (§29, §61 rule 12: "document numbers must be unique").
 *
 * ALLOCATED UNDER A ROW LOCK, and that is the whole design. The obvious
 * implementation — read `next_number`, use it, write back `next_number + 1`
 * — gives two concurrent sales the same number: both read 41, both use
 * INV-2026-000041, and the unique index rejects one of them with a 409 the
 * user did nothing to deserve. `SELECT ... FOR UPDATE` makes the second
 * request wait for the first to commit, so it reads 42.
 *
 * Must therefore be called inside the same transaction as the document it
 * numbers: the lock is only held until that transaction ends, and a number
 * allocated in its own transaction could be wasted (or reused) if the
 * document then failed to save.
 */

/** The document types §29 names, and the prefix each starts with. */
export const DOCUMENT_TYPES = {
  sale: "INV",
  order: "ORD",
  purchase: "PUR",
  return: "RET",
  transfer: "TRF",
  production: "PRD",
};

/**
 * Takes the next number for `documentType`, formatted per the business's
 * own configuration (§29 lets the business choose prefix, padding and
 * whether the year appears).
 *
 * Creates the sequence on first use rather than requiring every business to
 * be seeded with six rows it may never need.
 */
export async function nextDocumentNumber(conn, { businessId, documentType }) {
  const defaultPrefix = DOCUMENT_TYPES[documentType];
  if (!defaultPrefix) {
    // A type with no prefix is a programming error, not user input — it
    // would otherwise produce documents numbered "undefined-000001".
    throw errors.validation(`Unknown document type: ${documentType}`);
  }

  const year = new Date().getFullYear();

  // The row is created FIRST, and only then locked.
  //
  // The obvious order — lock, and insert if nothing was there — deadlocks on
  // a business's very first document. `SELECT ... FOR UPDATE` against a row
  // that does not exist takes a GAP lock rather than a row lock, so several
  // concurrent transactions each hold a gap lock over the same empty range;
  // each then tries to INSERT into that gap, needs an exclusive lock on it,
  // and waits for the others. MySQL kills one with ER_LOCK_DEADLOCK.
  //
  // An upsert has no such gap: the first INSERT takes the row lock, the rest
  // queue behind it and fall through to the (no-op) UPDATE branch, which
  // leaves them holding the same row lock the SELECT below re-reads under.
  await conn.query(
    `INSERT INTO document_sequences
       (business_id, document_type, prefix, next_number, number_padding, include_year, current_year)
     VALUES (?, ?, ?, 1, 6, TRUE, ?)
     ON DUPLICATE KEY UPDATE updated_at = updated_at`,
    [businessId, documentType, defaultPrefix, year]
  );

  const [rows] = await conn.query(
    `SELECT id, prefix, next_number, number_padding, include_year, current_year
       FROM document_sequences
      WHERE business_id = ? AND document_type = ?
      LIMIT 1
      FOR UPDATE`,
    [businessId, documentType]
  );
  const sequence = rows[0];

  // §29's yearly reset: a business that numbers by year expects the first
  // document of January to be 000001 again, not to continue from December.
  const resetForNewYear = Boolean(sequence.include_year) && sequence.current_year !== year;
  const number = resetForNewYear ? 1 : Number(sequence.next_number);

  await conn.query(
    `UPDATE document_sequences SET next_number = ?, current_year = ?, updated_at = NOW() WHERE id = ?`,
    [number + 1, year, sequence.id]
  );

  const padded = String(number).padStart(Number(sequence.number_padding), "0");
  return sequence.include_year
    ? `${sequence.prefix}-${year}-${padded}`
    : `${sequence.prefix}-${padded}`;
}
