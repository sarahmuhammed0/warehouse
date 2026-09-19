/// Categories (spec §7). `parentId == null` means a top-level category —
/// the same model represents both a category and a subcategory, matching
/// the spec's self-referential tree rather than two separate types.
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.code,
    this.description,
    this.imageUrl,
    this.parentId,
    this.parentName,
    required this.status,
    required this.sortOrder,
    required this.productCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String code;
  final String? description;
  final String? imageUrl;
  final String? parentId;
  final String? parentName;
  final CategoryStatus status;
  final int sortOrder;
  final int productCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isSubcategory => parentId != null;

  Category copyWith({
    String? name,
    String? code,
    String? description,
    String? imageUrl,
    String? parentId,
    String? parentName,
    bool clearParent = false,
    CategoryStatus? status,
    int? sortOrder,
    DateTime? updatedAt,
  }) {
    return Category(
      id: id,
      name: name ?? this.name,
      code: code ?? this.code,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      parentId: clearParent ? null : (parentId ?? this.parentId),
      parentName: clearParent ? null : (parentName ?? this.parentName),
      status: status ?? this.status,
      sortOrder: sortOrder ?? this.sortOrder,
      productCount: productCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

enum CategoryStatus { active, inactive }

/// The editable shape of a category — used for both create and edit forms,
/// deliberately without `id`/`createdAt`/`productCount` (server/repository-
/// assigned, never user-editable).
class CategoryDraft {
  const CategoryDraft({
    required this.name,
    required this.code,
    this.description,
    this.imageUrl,
    this.parentId,
    this.status = CategoryStatus.active,
    this.sortOrder = 0,
  });

  final String name;
  final String code;
  final String? description;
  final String? imageUrl;
  final String? parentId;
  final CategoryStatus status;
  final int sortOrder;
}
