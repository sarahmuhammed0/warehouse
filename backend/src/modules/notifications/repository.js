import { defineListSpec, buildWhere, buildOrderBy } from "../../db/listQuery.js";
import { queryAll, queryCount, pool } from "../../db/pool.js";

/** §31's notifications. */
const listSpec = defineListSpec({
  filters: {
    notificationType: {
      column: "n.notification_type",
      type: "enum",
      values: [
        "low_stock",
        "out_of_stock",
        "new_order",
        "return_request",
        "pending_payment",
        "production_completed",
        "transfer_received",
        "system_alert",
      ],
    },
  },
  search: { columns: ["n.title", "n.body"] },
  sort: {
    allowed: { createdAt: "n.created_at", notificationType: "n.notification_type" },
    default: { key: "createdAt", direction: "DESC" },
  },
  dateRange: { column: "n.created_at" },
});

/**
 * A business's notifications.
 *
 * Scoped to the business, not to one user: §31's events are things the BUSINESS
 * needs to know — stock has run out, an order arrived — and a shop where only
 * the person who happened to be logged in sees them is a shop that misses them.
 * A row may still name a user when it is genuinely personal, and those are
 * filtered to that user.
 */
export async function listNotifications({ businessId, userId, query, pagination, unreadOnly }) {
  const where = buildWhere(listSpec, query, { "n.business_id": businessId });

  // Either for everyone (user_id NULL) or for this user specifically.
  const scoped = `${where.sql} AND (n.user_id IS NULL OR n.user_id = ?)`;
  const params = [...where.params, userId];
  const unread = unreadOnly ? " AND n.read_at IS NULL" : "";
  const orderBy = buildOrderBy(listSpec, query, "n.id");

  const rows = await queryAll(
    `SELECT n.id, n.notification_type, n.title, n.body, n.reference_type,
            n.reference_id, n.read_at, n.created_at, n.user_id
       FROM notifications n ${scoped}${unread} ${orderBy} LIMIT ? OFFSET ?`,
    [...params, pagination.pageSize, pagination.offset]
  );

  const total = await queryCount(
    `SELECT COUNT(*) AS total FROM notifications n ${scoped}${unread}`,
    params
  );

  return { rows, total };
}

export async function unreadCount({ businessId, userId }) {
  const rows = await queryAll(
    `SELECT COUNT(*) AS total FROM notifications
      WHERE business_id = ? AND read_at IS NULL AND (user_id IS NULL OR user_id = ?)`,
    [businessId, userId]
  );
  return Number(rows[0]?.total ?? 0);
}

export async function markRead({ businessId, userId, id }) {
  const [result] = await pool.query(
    `UPDATE notifications SET read_at = NOW()
      WHERE id = ? AND business_id = ? AND (user_id IS NULL OR user_id = ?) AND read_at IS NULL`,
    [id, businessId, userId]
  );
  // Already read is success, not a 404 — the caller wanted it read, and it is.
  return result.affectedRows;
}

export async function markAllRead({ businessId, userId }) {
  const [result] = await pool.query(
    `UPDATE notifications SET read_at = NOW()
      WHERE business_id = ? AND read_at IS NULL AND (user_id IS NULL OR user_id = ?)`,
    [businessId, userId]
  );
  return result.affectedRows;
}

export async function notificationExists({ businessId, id }) {
  const rows = await queryAll(`SELECT 1 AS ok FROM notifications WHERE id = ? AND business_id = ? LIMIT 1`, [
    id,
    businessId,
  ]);
  return rows.length > 0;
}

/**
 * Writes a notification, unless the same one is already sitting there unread.
 *
 * The de-duplication is what makes this usable: stock crossing its threshold is
 * checked on every movement, so a product that is low stays low, and without
 * this a single afternoon of picking would bury the list under a hundred
 * identical "Low stock: Oak Plank" rows and the real alerts with them.
 *
 * Runs on the caller's connection when given one, so a notification raised by a
 * stock movement commits with that movement or not at all.
 */
export async function notify(
  conn,
  { businessId, userId = null, type, title, body, referenceType = null, referenceId = null }
) {
  const runner = conn ?? pool;

  const [existing] = await runner.query(
    `SELECT id FROM notifications
      WHERE business_id = ? AND notification_type = ? AND read_at IS NULL
        AND COALESCE(reference_type, '') = COALESCE(?, '')
        AND COALESCE(reference_id, 0) = COALESCE(?, 0)
      LIMIT 1`,
    [businessId, type, referenceType, referenceId]
  );
  if (existing.length > 0) return existing[0].id;

  const [result] = await runner.query(
    `INSERT INTO notifications
       (business_id, user_id, notification_type, title, body, reference_type, reference_id)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [businessId, userId, type, title, body, referenceType, referenceId]
  );
  return result.insertId;
}
