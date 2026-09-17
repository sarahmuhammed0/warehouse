/// Models foundation, feature-scoped (architecture §4) — mirrors the
/// backend's auth response shapes exactly (backend/src/modules/auth/
/// authService.js's `safeAccount`/`safeBusiness`). Deliberately has no
/// `passwordHash` field to even parse — the backend never sends one, and
/// modeling one here would be modeling a shape that should never exist.
library;

class AuthAccount {
  const AuthAccount({required this.id, required this.name, required this.phone});

  final int id;
  final String name;
  final String phone;

  factory AuthAccount.fromJson(Map<String, dynamic> json) =>
      AuthAccount(id: json['id'] as int, name: json['name'] as String, phone: json['phone'] as String);
}

class AuthBusiness {
  const AuthBusiness({
    required this.id,
    required this.name,
    required this.businessType,
    required this.logoUrl,
    required this.currency,
    required this.language,
    required this.timezone,
    required this.status,
  });

  final int id;
  final String name;
  final String businessType;
  final String? logoUrl;
  final String currency;
  final String language;
  final String timezone;
  final String status;

  factory AuthBusiness.fromJson(Map<String, dynamic> json) => AuthBusiness(
    id: json['id'] as int,
    name: json['name'] as String,
    businessType: json['businessType'] as String,
    logoUrl: json['logoUrl'] as String?,
    currency: json['currency'] as String,
    language: json['language'] as String,
    timezone: json['timezone'] as String,
    status: json['status'] as String,
  );
}

/// What a successful login returns: both tokens plus the identity/business
/// context the UI needs immediately (architecture §23) — nothing more.
class AuthSession {
  const AuthSession({required this.accessToken, required this.refreshToken, required this.account, this.business});

  final String accessToken;
  final String refreshToken;
  final AuthAccount account;
  final AuthBusiness? business; // null for a System Admin session

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    account: AuthAccount.fromJson(json['account'] as Map<String, dynamic>),
    business: json['business'] == null ? null : AuthBusiness.fromJson(json['business'] as Map<String, dynamic>),
  );
}

/// GET /me's shape — same identity fields, no tokens (the caller already has them).
class AuthIdentity {
  const AuthIdentity({required this.account, this.business});

  final AuthAccount account;
  final AuthBusiness? business;

  factory AuthIdentity.fromJson(Map<String, dynamic> json) => AuthIdentity(
    account: AuthAccount.fromJson(json['account'] as Map<String, dynamic>),
    business: json['business'] == null ? null : AuthBusiness.fromJson(json['business'] as Map<String, dynamic>),
  );
}

class RefreshedTokens {
  const RefreshedTokens({required this.accessToken, required this.refreshToken});
  final String accessToken;
  final String refreshToken;

  factory RefreshedTokens.fromJson(Map<String, dynamic> json) =>
      RefreshedTokens(accessToken: json['accessToken'] as String, refreshToken: json['refreshToken'] as String);
}

/// Which identity table Phase 1's two separate shells log into — mirrors
/// the backend's two account tables exactly (architecture §11: System
/// Admin and business users are structurally separate, never one type with
/// a flag). Determines which API routes a repository call hits
/// (`/api/auth/*` vs `/api/admin/auth/*`).
enum AccountType { businessUser, systemAdmin }
