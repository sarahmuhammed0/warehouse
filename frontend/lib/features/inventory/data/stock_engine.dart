import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_mode.dart';
import '../../dashboard/data/dashboard_metrics.dart';
import '../../products/data/product_providers.dart';
import 'inventory_models.dart';
import 'inventory_providers.dart';

/// One line of stock to move.
class StockChange {
  const StockChange({required this.productId, required this.productName, required this.delta});

  final String productId;
  final String productName;

  /// Negative consumes stock (a sale, a production run eating materials),
  /// positive adds it (a purchase arriving, a sellable return).
  final int delta;
}

/// The one place stock is allowed to move.
///
/// Before this existed, every module wrote its own record and stopped
/// there: you could sell a sofa, complete the order, and the sofa's
/// quantity never changed — the Sales list said one thing and Inventory
/// said another. `MovementType` had declared `sale`, `purchase`,
/// `returnMovement` and `production` from the start; nothing ever emitted
/// them.
///
/// Routing every module through here buys three things that are easy to
/// forget one call site at a time:
///
///  1. **Stock never moves without history.** A movement row and the
///     quantity change happen together (spec §12's append-only ledger), so
///     the Movements tab is a real audit trail rather than a list of manual
///     adjustments only.
///  2. **Every screen that shows a quantity is refreshed.** The products
///     list, the product detail, the inventory tabs, the pickers and the
///     dashboard all read different providers; [apply] invalidates the lot.
///  3. **Reversal is symmetric.** Cancelling after completing calls the
///     same method with negated deltas, so demo stock can't drift.
class StockEngine {
  const StockEngine(this._ref);

  final Ref _ref;

  /// The movement types the SERVER owns in backend mode.
  ///
  /// Each of these is stock moving because a document changed state —
  /// confirming an order, receiving a purchase, completing a return or a
  /// production run — and the backend moves it inside the same transaction
  /// that changed the document, writing its own ledger row with the document
  /// as the reference (§12). Moving it here as well would move it twice and
  /// file a second, manual-looking row on top of the document's own.
  ///
  /// A manual adjustment is not in this set, and must not be: nothing else
  /// records it, so in backend mode it still goes to the inventory endpoint
  /// like any other user action.
  static const _serverOwned = {
    MovementType.sale,
    MovementType.purchase,
    MovementType.returnMovement,
    MovementType.production,
  };

  /// Applies [changes] as one logical event, writing a movement row per
  /// line. Lines with a zero delta still record a movement — a damaged
  /// return is a real event that moved no sellable stock.
  Future<void> apply(
    List<StockChange> changes, {
    required MovementType type,
    String? note,
  }) async {
    if (changes.isEmpty) return;

    if (AppModeConfig.mode == AppMode.backend && _serverOwned.contains(type)) {
      // The stock has already moved, server-side. What the calling screen
      // still needs is for every provider showing a quantity to re-read it.
      await _refreshEverythingThatShowsAQuantity();
      return;
    }

    final inventory = _ref.read(inventoryRepositoryProvider);
    final products = _ref.read(productRepositoryProvider);

    for (final change in changes) {
      // Read the live quantity rather than trusting a value the caller
      // captured earlier — two movements in one event must not both record
      // the same "previous quantity".
      int currentQuantity;
      try {
        currentQuantity = (await products.getById(change.productId)).currentQuantity;
      } catch (_) {
        // A line referencing a product that no longer exists (deleted in a
        // long demo session) must not abort the whole event.
        continue;
      }

      await inventory.recordAdjustment(
        productId: change.productId,
        productName: change.productName,
        currentQuantity: currentQuantity,
        delta: change.delta,
        type: type,
        note: note,
      );
      if (change.delta != 0) {
        await products.adjustQuantity(change.productId, change.delta);
      }
    }

    await _refreshEverythingThatShowsAQuantity();
  }

  /// The mirror image of [apply] — used when a completed document is
  /// cancelled or reversed.
  Future<void> reverse(
    List<StockChange> changes, {
    required MovementType type,
    String? note,
  }) {
    return apply(
      [for (final c in changes) StockChange(productId: c.productId, productName: c.productName, delta: -c.delta)],
      type: type,
      note: note,
    );
  }

  Future<void> _refreshEverythingThatShowsAQuantity() async {
    await _ref.read(productListControllerProvider.notifier).reload();
    await _ref.read(movementListControllerProvider.notifier).reload();
    _ref.invalidate(productPickerOptionsProvider);
    _ref.invalidate(dashboardMetricsProvider);
  }
}

final stockEngineProvider = Provider<StockEngine>(StockEngine.new);
