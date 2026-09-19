import '../../../core/network/paginated_result.dart';
import '../../../core/repositories/demo_data_source.dart';
import '../../../core/repositories/paged_query.dart';
import 'category_models.dart';

/// The interface every screen depends on — `LocalCategoryRepository` today,
/// an `ApiCategoryRepository` later (§3: "design the repository/service
/// interfaces so the backend can replace the local implementation later
/// without rewriting screens"). Nothing outside `features/categories/data/`
/// should ever import `LocalCategoryRepository` directly.
abstract class CategoryRepository {
  Future<PaginatedResult<Category>> list(PagedQuery query);

  /// For parent-category pickers — unpaginated, active categories only,
  /// intentionally small enough that fetching "all" is reasonable here
  /// (nothing like this exists for Products/Orders, which are `list()`-only).
  Future<List<Category>> allForPicker();

  Future<Category> getById(String id);
  Future<Category> create(CategoryDraft draft);
  Future<Category> update(String id, CategoryDraft draft);
  Future<void> setStatus(String id, CategoryStatus status);
}

class LocalCategoryRepository with DemoRepository implements CategoryRepository {
  LocalCategoryRepository() {
    _seed();
  }

  final List<Category> _items = [];
  int _nextId = 1;

  void _seed() {
    final now = DateTime.now();
    final topLevel = [
      ('Living Room', 'LIV'),
      ('Bedroom', 'BED'),
      ('Office Furniture', 'OFF'),
      ('Raw Materials', 'RAW'),
      ('Hardware & Fittings', 'HDW'),
    ];
    for (final (name, code) in topLevel) {
      _items.add(
        Category(
          id: 'cat-${_nextId++}',
          name: name,
          code: code,
          description: null,
          imageUrl: null,
          parentId: null,
          parentName: null,
          status: CategoryStatus.active,
          sortOrder: _items.length,
          productCount: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    final livingRoom = _items[0];
    final subcats = [
      ('Sofas', 'LIV-SOF'),
      ('Coffee Tables', 'LIV-CTB'),
      ('TV Units', 'LIV-TVU'),
    ];
    for (final (name, code) in subcats) {
      _items.add(
        Category(
          id: 'cat-${_nextId++}',
          name: name,
          code: code,
          description: null,
          imageUrl: null,
          parentId: livingRoom.id,
          parentName: livingRoom.name,
          status: CategoryStatus.active,
          sortOrder: _items.length,
          productCount: 0,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    _items.add(
      Category(
        id: 'cat-${_nextId++}',
        name: 'Discontinued Line',
        code: 'DISC',
        description: 'Kept for historical order records only.',
        imageUrl: null,
        parentId: null,
        parentName: null,
        status: CategoryStatus.inactive,
        sortOrder: _items.length,
        productCount: 0,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Future<PaginatedResult<Category>> list(PagedQuery query) async {
    await simulatedLatency();
    var pool = List<Category>.from(_items);
    final statusFilter = query.filters['status'] as CategoryStatus?;
    if (statusFilter != null) {
      pool = pool.where((c) => c.status == statusFilter).toList();
    }
    final parentFilter = query.filters['parentId'] as String?;
    if (parentFilter != null) {
      pool = pool.where((c) => c.parentId == parentFilter).toList();
    }
    return paginateInMemory<Category>(
      pool,
      query,
      matches: (item, q) =>
          item.name.toLowerCase().contains(q) || item.code.toLowerCase().contains(q),
      sortKey: (item) => item.sortOrder,
    );
  }

  @override
  Future<List<Category>> allForPicker() async {
    await simulatedLatency();
    return _items.where((c) => c.status == CategoryStatus.active).toList();
  }

  @override
  Future<Category> getById(String id) async {
    await simulatedLatency();
    return _items.firstWhere((c) => c.id == id, orElse: () => throw StateError('Category not found'));
  }

  @override
  Future<Category> create(CategoryDraft draft) async {
    await simulatedLatency();
    final parent = draft.parentId == null
        ? null
        : _items.firstWhere((c) => c.id == draft.parentId, orElse: () => throw StateError('Parent not found'));
    final now = DateTime.now();
    final created = Category(
      id: 'cat-${_nextId++}',
      name: draft.name,
      code: draft.code,
      description: draft.description,
      imageUrl: draft.imageUrl,
      parentId: parent?.id,
      parentName: parent?.name,
      status: draft.status,
      sortOrder: draft.sortOrder,
      productCount: 0,
      createdAt: now,
      updatedAt: now,
    );
    _items.add(created);
    return created;
  }

  @override
  Future<Category> update(String id, CategoryDraft draft) async {
    await simulatedLatency();
    final index = _items.indexWhere((c) => c.id == id);
    if (index == -1) throw StateError('Category not found');
    final parent = draft.parentId == null
        ? null
        : _items.firstWhere((c) => c.id == draft.parentId, orElse: () => throw StateError('Parent not found'));
    final updated = _items[index].copyWith(
      name: draft.name,
      code: draft.code,
      description: draft.description,
      imageUrl: draft.imageUrl,
      parentId: parent?.id,
      parentName: parent?.name,
      clearParent: parent == null,
      status: draft.status,
      sortOrder: draft.sortOrder,
      updatedAt: DateTime.now(),
    );
    _items[index] = updated;
    return updated;
  }

  @override
  Future<void> setStatus(String id, CategoryStatus status) async {
    await simulatedLatency();
    final index = _items.indexWhere((c) => c.id == id);
    if (index == -1) throw StateError('Category not found');
    _items[index] = _items[index].copyWith(status: status, updatedAt: DateTime.now());
  }
}
