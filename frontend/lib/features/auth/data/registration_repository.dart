import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/providers.dart';

/// What a business supplies when it applies for an account. Exactly the
/// fields an administrator would otherwise have typed on its behalf
/// (§2's "create factory/warehouse/storage-store accounts"), so approving is
/// a decision rather than a data-entry job.
class RegistrationDraft {
  const RegistrationDraft({
    required this.businessName,
    required this.businessType,
    required this.businessPhone,
    required this.ownerName,
    required this.ownerPhone,
    required this.password,
    this.currency,
    this.language,
    this.timezone,
  });

  final String businessName;

  /// One of the backend's `business_type` values, e.g. `furniture_factory`.
  final String businessType;
  final String businessPhone;
  final String ownerName;
  final String ownerPhone;
  final String password;
  final String? currency;
  final String? language;
  final String? timezone;

  Map<String, dynamic> toJson() => {
    'name': businessName,
    'businessType': businessType,
    'phone': businessPhone,
    if (currency != null) 'currency': currency,
    if (language != null) 'language': language,
    if (timezone != null) 'timezone': timezone,
    'owner': {'name': ownerName, 'phone': ownerPhone, 'password': password},
  };
}

/// The backend's answer. It is deliberately the same whether or not the
/// phone was already registered (§58 — a public endpoint must not become a
/// way to discover which numbers have accounts), so there is nothing here to
/// distinguish those cases and the UI must not try.
class RegistrationResult {
  const RegistrationResult({required this.status, required this.message});

  /// Always `pending`: a registration never creates a usable account.
  final String status;
  final String message;

  factory RegistrationResult.fromJson(Map<String, dynamic> json) => RegistrationResult(
    status: (json['status'] as String?) ?? 'pending',
    message: (json['message'] as String?) ?? '',
  );
}

abstract class RegistrationRepository {
  Future<RegistrationResult> register(RegistrationDraft draft);
}

class ApiRegistrationRepository implements RegistrationRepository {
  ApiRegistrationRepository(this._client);

  final ApiClient _client;

  @override
  Future<RegistrationResult> register(RegistrationDraft draft) async {
    // Public endpoint: no token is attached, and the backend answers 202
    // because the account exists but cannot be used yet.
    final json = await _client.postJson('/registration', draft.toJson());
    return RegistrationResult.fromJson(json);
  }
}

/// Demo-mode stand-in, so the sign-up screen is reachable and exercisable
/// with the backend off — matching how `DemoAuthRepository` lets the login
/// screen work. It accepts anything and reports the same pending result the
/// real backend would; it stores nothing, because a demo registration has
/// no administrator to approve it.
class DemoRegistrationRepository implements RegistrationRepository {
  @override
  Future<RegistrationResult> register(RegistrationDraft draft) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const RegistrationResult(
      status: 'pending',
      message: 'Your registration has been received and is awaiting review.',
    );
  }
}

final registrationRepositoryProvider = Provider<RegistrationRepository>((ref) {
  return switch (AppModeConfig.mode) {
    AppMode.backend => ApiRegistrationRepository(ref.watch(apiClientProvider)),
    AppMode.demo => DemoRegistrationRepository(),
  };
});
