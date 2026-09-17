// One small adapter per identity table, so authService.js's login/refresh/
// logout/change-password logic is written exactly once and reused by both
// `/api/auth/*` (business users) and `/api/admin/auth/*` (System Admins) —
// without ever merging the two tables or routes together. See
// docs/authentication.md "System Admin isolation" for why they stay two
// tables instead of one with a flag.

import * as repo from "./repository.js";

export const businessUserAdapter = {
  accountType: "business_user",
  findByPhone: repo.findUserByPhone,
  findById: repo.findUserById,
  updateLastLogin: repo.updateUserLastLogin,
  updatePasswordHash: repo.updateUserPasswordHash,
  findPasswordHash: repo.findUserPasswordHash,
  createRefreshToken: ({ subjectId, ...rest }) => repo.createUserRefreshToken({ userId: subjectId, ...rest }),
  findRefreshTokenByHash: async (hash) => {
    const row = await repo.findUserRefreshTokenByHash(hash);
    return row ? { ...row, subjectId: row.user_id } : null;
  },
  revokeRefreshToken: repo.revokeUserRefreshToken,
  revokeAllRefreshTokens: repo.revokeAllUserRefreshTokens,
  /** Business users carry a businessId into the JWT/audit trail; admins don't. */
  businessIdFor: (account) => account.business_id,
};

export const systemAdminAdapter = {
  accountType: "system_admin",
  findByPhone: repo.findSystemAdminByPhone,
  findById: repo.findSystemAdminById,
  updateLastLogin: repo.updateSystemAdminLastLogin,
  updatePasswordHash: repo.updateSystemAdminPasswordHash,
  findPasswordHash: repo.findSystemAdminPasswordHash,
  createRefreshToken: ({ subjectId, ...rest }) => repo.createAdminRefreshToken({ adminId: subjectId, ...rest }),
  findRefreshTokenByHash: async (hash) => {
    const row = await repo.findAdminRefreshTokenByHash(hash);
    return row ? { ...row, subjectId: row.system_admin_id } : null;
  },
  revokeRefreshToken: repo.revokeAdminRefreshToken,
  revokeAllRefreshTokens: repo.revokeAllAdminRefreshTokens,
  businessIdFor: () => null,
};
