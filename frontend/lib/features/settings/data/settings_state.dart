import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final businessSettingsProvider = NotifierProvider<BusinessSettingsController, BusinessSettingsData>(BusinessSettingsController.new);

class BusinessSettingsController extends Notifier<BusinessSettingsData> {
  @override
  BusinessSettingsData build() => const BusinessSettingsData();

  void update(BusinessSettingsData Function(BusinessSettingsData current) updater) {
    state = updater(state);
  }
}
