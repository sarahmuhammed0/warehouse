import '../../inventory/data/stock_engine.dart';
import 'order_models.dart';

/// The stock movement an order represents: every line leaves the shelf.
///
/// Shared by the sale form (a quick sale is completed on creation) and the
/// order detail screen (a standard order moves stock when it reaches
/// Completed), so the two paths cannot disagree about what a given order
/// does to inventory — and so cancelling a completed order can hand the
/// exact same list to `StockEngine.reverse`.
List<StockChange> stockChangesFor(Order order) => [
      for (final item in order.items)
        StockChange(productId: item.productId, productName: item.productName, delta: -item.quantity),
    ];
