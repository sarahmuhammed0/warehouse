import { z } from "zod";

// Loose on shape here (just "non-empty string") — the real E.164 shape
// check happens in authService.login via isValidE164, which is reused
// as-is by both /api/auth and /api/admin/auth. Keeping strict format
// validation out of this schema means a malformed phone reaches the same
// generic "Invalid phone number or password" path as a wrong password,
// rather than a distinguishable 422 that would leak "at least this phone
// is not even a real shape."
export const loginSchema = z.object({
  phone: z.string().trim().min(1, "Phone number is required."),
  password: z.string().min(1, "Password is required."),
});

export const changePasswordSchema = z.object({
  currentPassword: z.string().min(1, "Current password is required."),
  newPassword: z.string().min(8, "New password must be at least 8 characters."),
});

export const refreshSchema = z.object({
  refreshToken: z.string().min(1, "Refresh token is required."),
});
