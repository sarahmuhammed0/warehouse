import '../../../core/network/api_client.dart';
import 'settings_state.dart';

/// Where a Settings screen's values come from and go to.
///
/// The screen edits one flat [BusinessSettingsData]; the server keeps those
/// values in four quite different places — the business record (§34), the
/// settings key/value store (§43/§44/§47), the document sequences (§29) and
/// the PDF template (§28). Reassembling them into one object, and taking one
/// apart again on save, is this class's whole job.
abstract class SettingsRepository {
  Future<BusinessSettingsData> load();

  /// Writes only what actually changed between [previous] and [next].
  ///
  /// A diff rather than a blanket write, because these endpoints are not one
  /// endpoint: saving everything on every keystroke would PATCH the business
  /// record, the settings store, four document sequences and the PDF template
  /// each time, and a numbering counter that only moves forward would start
  /// refusing writes it never needed to be sent.
  Future<void> save({required BusinessSettingsData previous, required BusinessSettingsData next});
}

/// Demo mode: the defaults, and saving keeps them in memory only.
///
/// Deliberately not persisted anywhere — §48's rule is never to let a local
/// toggle look like durable state, and in demo mode there is nothing durable
/// for it to be.
class LocalSettingsRepository implements SettingsRepository {
  @override
  Future<BusinessSettingsData> load() async => const BusinessSettingsData();

  @override
  Future<void> save({required BusinessSettingsData previous, required BusinessSettingsData next}) async {}
}

class ApiSettingsRepository implements SettingsRepository {
  ApiSettingsRepository(this._client);

  final ApiClient _client;

  /// Which document sequence backs each prefix field on the screen.
  static const _invoiceSequence = 'sale';
  static const _orderSequence = 'order';
  static const _productionSequence = 'production';

  @override
  Future<BusinessSettingsData> load() async {
    // Four reads, run together — they are independent, and the screen is
    // waiting for all of them.
    final results = await Future.wait([
      _client.getJson('/business'),
      _client.getJson('/settings'),
      _client.getList('/documents/numbering'),
      _client.getJson('/documents/pdf-template'),
    ]);

    final business = results[0] as Map<String, dynamic>;
    final settings = (results[1] as Map<String, dynamic>)['values'] as Map<String, dynamic>? ?? const {};
    final numbering = <String, Map<String, dynamic>>{
      for (final row in (results[2] as ({List<dynamic> data, Map<String, dynamic> meta})).data)
        '${(row as Map<String, dynamic>)['documentType']}': row,
    };
    final template = results[3] as Map<String, dynamic>;
    final fields = (template['fields'] as Map<String, dynamic>?) ?? const {};

    const defaults = BusinessSettingsData();
    return BusinessSettingsData(
      businessName: (business['name'] as String?) ?? defaults.businessName,
      currency: (business['currency'] as String?) ?? defaults.currency,
      negativeInventoryAllowed:
          settings['inventory.allow_negative_stock'] as bool? ?? defaults.negativeInventoryAllowed,
      lowStockDefaultThreshold: (settings['inventory.low_stock_threshold_default'] as num?)?.toInt() ??
          defaults.lowStockDefaultThreshold,
      invoicePrefix: numbering[_invoiceSequence]?['prefix'] as String? ?? defaults.invoicePrefix,
      orderPrefix: numbering[_orderSequence]?['prefix'] as String? ?? defaults.orderPrefix,
      // One field on screen, and every document type has its own counter. It
      // shows the invoice sequence, which is the one a business actually asks
      // about — see `save` for why writing it is narrower than reading it.
      startingNumber: (numbering[_invoiceSequence]?['nextNumber'] as num?)?.toInt() ?? defaults.startingNumber,
      cashPaymentsEnabled: settings['payments.cash_enabled'] as bool? ?? defaults.cashPaymentsEnabled,
      bankTransferEnabled: settings['payments.bank_transfer_enabled'] as bool? ?? defaults.bankTransferEnabled,
      cardPaymentsEnabled: settings['payments.card_enabled'] as bool? ?? defaults.cardPaymentsEnabled,
      pdfShowLogo: fields['logo'] as bool? ?? defaults.pdfShowLogo,
      pdfShowTaxInfo: fields['taxInfo'] as bool? ?? defaults.pdfShowTaxInfo,
      pdfShowSignature: fields['signature'] as bool? ?? defaults.pdfShowSignature,
      pdfFooterText: (template['footerText'] as String?) ?? defaults.pdfFooterText,
      productionNumberPrefix:
          numbering[_productionSequence]?['prefix'] as String? ?? defaults.productionNumberPrefix,
      minPasswordLength: (settings['security.min_password_length'] as num?)?.toInt() ?? defaults.minPasswordLength,
      // Neither of these is a stored setting, and the two reasons differ.
      //
      // `sessionTimeoutMinutes` is the access token's lifetime, fixed when the
      // token is signed. `loginLockoutAttempts` is deliberately NOT per
      // business: the lockout is checked before a phone is resolved to an
      // account, precisely so the response cannot reveal whether the account
      // exists, and reading a per-business threshold would require looking it
      // up first. Both are left at the defaults the screen already shows, and
      // `save` never sends them — see docs/frontend-wiring.md.
      sessionTimeoutMinutes: defaults.sessionTimeoutMinutes,
      loginLockoutAttempts: defaults.loginLockoutAttempts,
    );
  }

  @override
  Future<void> save({required BusinessSettingsData previous, required BusinessSettingsData next}) async {
    // 1. The business record (§34).
    final business = <String, dynamic>{
      if (next.businessName != previous.businessName) 'name': next.businessName,
      if (next.currency != previous.currency) 'currency': next.currency,
    };
    if (business.isNotEmpty) await _client.patchJson('/business', business);

    // 2. The settings store (§43/§44/§47). Sent as one PATCH: they are one
    //    endpoint, and a half-applied group is worse than a rejected one.
    final values = <String, dynamic>{
      if (next.negativeInventoryAllowed != previous.negativeInventoryAllowed)
        'inventory.allow_negative_stock': next.negativeInventoryAllowed,
      if (next.lowStockDefaultThreshold != previous.lowStockDefaultThreshold)
        'inventory.low_stock_threshold_default': next.lowStockDefaultThreshold,
      if (next.cashPaymentsEnabled != previous.cashPaymentsEnabled)
        'payments.cash_enabled': next.cashPaymentsEnabled,
      if (next.bankTransferEnabled != previous.bankTransferEnabled)
        'payments.bank_transfer_enabled': next.bankTransferEnabled,
      if (next.cardPaymentsEnabled != previous.cardPaymentsEnabled)
        'payments.card_enabled': next.cardPaymentsEnabled,
      if (next.minPasswordLength != previous.minPasswordLength)
        'security.min_password_length': next.minPasswordLength,
    };
    if (values.isNotEmpty) await _client.patchJson('/settings', {'values': values});

    // 3. Document numbering (§29), one call per sequence that changed.
    await _saveSequence(_invoiceSequence, {
      if (next.invoicePrefix != previous.invoicePrefix) 'prefix': next.invoicePrefix,
      // Only ever sent for the invoice sequence, because that is the one the
      // single "Starting number" field reads. Applying it to all four would
      // renumber purchases and returns from a box the screen never claimed was
      // about them.
      if (next.startingNumber != previous.startingNumber) 'nextNumber': next.startingNumber,
    });
    await _saveSequence(_orderSequence, {
      if (next.orderPrefix != previous.orderPrefix) 'prefix': next.orderPrefix,
    });
    await _saveSequence(_productionSequence, {
      if (next.productionNumberPrefix != previous.productionNumberPrefix)
        'prefix': next.productionNumberPrefix,
    });

    // 4. The PDF template (§28). PUT, because `fields` is a whole set.
    final pdfChanged = next.pdfShowLogo != previous.pdfShowLogo ||
        next.pdfShowTaxInfo != previous.pdfShowTaxInfo ||
        next.pdfShowSignature != previous.pdfShowSignature ||
        next.pdfFooterText != previous.pdfFooterText;
    if (pdfChanged) {
      await _client.putJson('/documents/pdf-template', {
        'footerText': next.pdfFooterText,
        'fields': {
          'logo': next.pdfShowLogo,
          'taxInfo': next.pdfShowTaxInfo,
          'signature': next.pdfShowSignature,
        },
      });
    }
  }

  Future<void> _saveSequence(String documentType, Map<String, dynamic> body) async {
    if (body.isEmpty) return;
    await _client.patchJson('/documents/numbering/$documentType', body);
  }
}
