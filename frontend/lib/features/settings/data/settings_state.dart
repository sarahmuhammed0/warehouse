import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/network/providers.dart';
import 'settings_repository.dart';

/// Every Settings section's draft state — in-memory only, same reasoning as
/// `theme_controller.dart`/`locale_controller.dart`: there is no backend
/// Settings endpoint yet to persist any of this to (§48: never pretend a
/// local toggle is durable state). Kept as one controller since Settings'
/// sections are all small, related preferences, not independent entities
/// with their own CRUD lifecycle (unlike Products/Customers/etc.).
class BusinessSettingsData {
  const BusinessSettingsData({
    this.businessName = 'Warehouse OS Demo Business',
    this.currency = 'USD',
    this.negativeInventoryAllowed = false,
    this.lowStockDefaultThreshold = 5,
    this.invoicePrefix = 'INV',
    this.orderPrefix = 'ORD',
    this.startingNumber = 1,
    this.cashPaymentsEnabled = true,
    this.bankTransferEnabled = true,
    this.cardPaymentsEnabled = false,
    this.pdfShowLogo = true,
    this.pdfShowTaxInfo = true,
    this.pdfShowSignature = true,
    this.pdfFooterText = 'Thank you for your business.',
    this.productionNumberPrefix = 'PRDN',
    this.minPasswordLength = 8,
    this.sessionTimeoutMinutes = 30,
    this.loginLockoutAttempts = 5,
  });

  final String businessName;
  final String currency;
  final bool negativeInventoryAllowed;
  final int lowStockDefaultThreshold;
  final String invoicePrefix;
  final String orderPrefix;
  final int startingNumber;
  final bool cashPaymentsEnabled;
  final bool bankTransferEnabled;
  final bool cardPaymentsEnabled;
  final bool pdfShowLogo;
  final bool pdfShowTaxInfo;
  final bool pdfShowSignature;
  final String pdfFooterText;
  final String productionNumberPrefix;
  final int minPasswordLength;
  final int sessionTimeoutMinutes;
  final int loginLockoutAttempts;

  BusinessSettingsData copyWith({
    String? businessName,
    String? currency,
    bool? negativeInventoryAllowed,
    int? lowStockDefaultThreshold,
    String? invoicePrefix,
    String? orderPrefix,
    int? startingNumber,
    bool? cashPaymentsEnabled,
    bool? bankTransferEnabled,
    bool? cardPaymentsEnabled,
    bool? pdfShowLogo,
    bool? pdfShowTaxInfo,
    bool? pdfShowSignature,
    String? pdfFooterText,
    String? productionNumberPrefix,
    int? minPasswordLength,
    int? sessionTimeoutMinutes,
    int? loginLockoutAttempts,
  }) {
    return BusinessSettingsData(
      businessName: businessName ?? this.businessName,
      currency: currency ?? this.currency,
      negativeInventoryAllowed: negativeInventoryAllowed ?? this.negativeInventoryAllowed,
      lowStockDefaultThreshold: lowStockDefaultThreshold ?? this.lowStockDefaultThreshold,
      invoicePrefix: invoicePrefix ?? this.invoicePrefix,
      orderPrefix: orderPrefix ?? this.orderPrefix,
      startingNumber: startingNumber ?? this.startingNumber,
      cashPaymentsEnabled: cashPaymentsEnabled ?? this.cashPaymentsEnabled,
      bankTransferEnabled: bankTransferEnabled ?? this.bankTransferEnabled,
      cardPaymentsEnabled: cardPaymentsEnabled ?? this.cardPaymentsEnabled,
      pdfShowLogo: pdfShowLogo ?? this.pdfShowLogo,
      pdfShowTaxInfo: pdfShowTaxInfo ?? this.pdfShowTaxInfo,
      pdfShowSignature: pdfShowSignature ?? this.pdfShowSignature,
      pdfFooterText: pdfFooterText ?? this.pdfFooterText,
      productionNumberPrefix: productionNumberPrefix ?? this.productionNumberPrefix,
      minPasswordLength: minPasswordLength ?? this.minPasswordLength,
      sessionTimeoutMinutes: sessionTimeoutMinutes ?? this.sessionTimeoutMinutes,
      loginLockoutAttempts: loginLockoutAttempts ?? this.loginLockoutAttempts,
    );
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return switch (AppModeConfig.mode) {
    AppMode.backend => ApiSettingsRepository(ref.watch(apiClientProvider)),
    AppMode.demo => LocalSettingsRepository(),
  };
});

final businessSettingsProvider = NotifierProvider<BusinessSettingsController, BusinessSettingsData>(BusinessSettingsController.new);

class BusinessSettingsController extends Notifier<BusinessSettingsData> {
  /// The last values known to match the server. `save` diffs against this, not
  /// against the previous keystroke, so a field edited three times still sends
  /// one change rather than three.
  BusinessSettingsData _saved = const BusinessSettingsData();

  Timer? _debounce;

  /// Set once the first load has come back, so a save cannot fire against the
  /// defaults and overwrite real values with them — which is exactly what
  /// would happen if the screen were touched while the load was still in
  /// flight.
  bool _loaded = false;

  @override
  BusinessSettingsData build() {
    ref.onDispose(() => _debounce?.cancel());

    if (AppModeConfig.mode == AppMode.demo) {
      _loaded = true;
      return const BusinessSettingsData();
    }

    // Starts at the defaults and is replaced when the server answers. The
    // screen's fields re-seed themselves when that happens — see
    // `SettingsField.didUpdateWidget`.
    Future.microtask(reload);
    return const BusinessSettingsData();
  }

  Future<void> reload() async {
    try {
      final loaded = await ref.read(settingsRepositoryProvider).load();
      _saved = loaded;
      _loaded = true;
      state = loaded;
    } catch (_) {
      // Leaves the defaults on screen. `_loaded` stays false, so nothing is
      // saved over values that were never read — a failed load must not turn
      // into a write that makes the defaults true.
    }
  }

  /// The screen has no Save button: every field writes through as it is
  /// edited. So the write is debounced rather than sent per keystroke, and
  /// only the fields that actually differ are sent.
  void update(BusinessSettingsData Function(BusinessSettingsData current) updater) {
    state = updater(state);
    if (AppModeConfig.mode == AppMode.demo) return;

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _flush);
  }

  Future<void> _flush() async {
    if (!_loaded) return;
    final previous = _saved;
    final next = state;
    try {
      await ref.read(settingsRepositoryProvider).save(previous: previous, next: next);
      _saved = next;
    } catch (_) {
      // The server refused something — a prefix that is too long, a numbering
      // counter asked to move backwards, a password minimum below the system
      // floor. Re-reading puts the screen back in step with what was actually
      // stored, rather than leaving it showing a value that was not saved.
      await reload();
    }
  }
}
