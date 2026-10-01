import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_mode.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/providers.dart';

/// One extra field a business keeps on its products (§51).
class CustomFieldDefinition {
  const CustomFieldDefinition({required this.id, required this.label, required this.fieldKey});

  final String id;
  final String label;
  final String fieldKey;
}

/// Custom field DEFINITIONS — what extra fields exist, not what any record
/// holds in them. The values belong to the record they describe and are saved
/// with it, because a product's extra fields are part of that product.
abstract class CustomFieldsRepository {
  Future<List<CustomFieldDefinition>> list();
  Future<void> create(String label);
  Future<void> delete(String id);
}

/// Demo mode: two examples, held in memory for the session.
class LocalCustomFieldsRepository implements CustomFieldsRepository {
  final List<CustomFieldDefinition> _items = [
    const CustomFieldDefinition(id: 'cf-1', label: 'Wood type', fieldKey: 'wood_type'),
    const CustomFieldDefinition(id: 'cf-2', label: 'Fabric type', fieldKey: 'fabric_type'),
  ];
  int _next = 3;

  @override
  Future<List<CustomFieldDefinition>> list() async => List.of(_items);

  @override
  Future<void> create(String label) async {
    _items.add(CustomFieldDefinition(id: 'cf-${_next++}', label: label, fieldKey: keyFor(label)));
  }

  @override
  Future<void> delete(String id) async => _items.removeWhere((f) => f.id == id);
}

class ApiCustomFieldsRepository implements CustomFieldsRepository {
  ApiCustomFieldsRepository(this._client);

  final ApiClient _client;

  /// The settings screen collects a product field, which is what §51's example
  /// is about and the only entity this section offers.
  static const _entityType = 'product';

  @override
  Future<List<CustomFieldDefinition>> list() async {
    final result = await _client.getList('/custom-fields?entityType=$_entityType');
    return result.data
        .cast<Map<String, dynamic>>()
        .map((row) => CustomFieldDefinition(
              id: '${row['id']}',
              label: (row['label'] as String?) ?? '',
              fieldKey: (row['fieldKey'] as String?) ?? '',
            ))
        .toList();
  }

  /// The screen collects a label. The server also needs a machine key, because
  /// the label is what a business renames and the key is what recorded values
  /// are filed under — so renaming "Wood type" must not orphan every value
  /// already stored against it. The key is derived once, here, at creation.
  @override
  Future<void> create(String label) async {
    await _client.postJson('/custom-fields', {
      'entityType': _entityType,
      'label': label,
      'fieldKey': keyFor(label),
      'fieldType': 'text',
    });
  }

  /// Retires the field. §51 keeps its values: a business that stopped
  /// collecting something has not decided it never happened.
  @override
  Future<void> delete(String id) async => _client.deleteJson('/custom-fields/$id').then((_) {});
}

/// "Wood type" becomes `wood_type`. Must match the server's rule — lowercase
/// letters, digits and underscores, starting with a letter.
String keyFor(String label) {
  final slug = label
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  // A label written entirely in a non-Latin script leaves nothing usable, and
  // an empty key would be refused with a message about a rule the user never
  // saw. A stable fallback keeps the field creatable; its LABEL is what they
  // actually read on screen.
  if (slug.isEmpty || !RegExp(r'^[a-z]').hasMatch(slug)) {
    return 'field_${DateTime.now().millisecondsSinceEpoch}';
  }
  return slug.length > 64 ? slug.substring(0, 64) : slug;
}

final customFieldsRepositoryProvider = Provider<CustomFieldsRepository>((ref) {
  return switch (AppModeConfig.mode) {
    AppMode.backend => ApiCustomFieldsRepository(ref.watch(apiClientProvider)),
    AppMode.demo => LocalCustomFieldsRepository(),
  };
});

final customFieldsProvider = FutureProvider.autoDispose<List<CustomFieldDefinition>>((ref) {
  return ref.watch(customFieldsRepositoryProvider).list();
});
