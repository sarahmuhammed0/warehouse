import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Why a navigation item is asking to be looked at.
///
/// Three kinds, because they are three different claims on someone's attention
/// and collapsing them would make all of them mean "something, somewhere".
enum NavIndicatorKind {
  /// Someone has to decide or do something, and nothing proceeds until they
  /// do — a business registration waiting to be approved or rejected. Red,
  /// because it is a queue with a person at the other end of it.
  pendingAction,

  /// Something arrived that has not been read. Not blocking anyone; it just
  /// has not been seen yet.
  unread,

  /// Something is wrong and worth looking at, but nobody is waiting on a
  /// decision — a failed backup, stock below its threshold.
  warning,
}

/// What a navigation item should show, if anything.
///
/// A count of zero means NOTHING is rendered. That is the whole contract: these
/// are built from live data, so an item carries a badge exactly as long as the
/// thing behind it is still outstanding, and loses it when the work is done —
/// without anyone having to remember to clear it.
@immutable
class NavIndicator {
  const NavIndicator({required this.count, required this.kind});

  const NavIndicator.pendingAction(this.count) : kind = NavIndicatorKind.pendingAction;

  /// Records that arrived since the item was last opened. Clears by looking,
  /// unlike [NavIndicator.pendingAction], which clears only by deciding.
  const NavIndicator.unread(this.count) : kind = NavIndicatorKind.unread;

  final int count;
  final NavIndicatorKind kind;

  bool get isVisible => count > 0;

  @override
  bool operator ==(Object other) =>
      other is NavIndicator && other.count == count && other.kind == kind;

  @override
  int get hashCode => Object.hash(count, kind);
}

/// Wraps [child] with the badge for [indicator], or returns it untouched.
///
/// Both halves matter. A caller does not have to ask whether there is anything
/// to show, and an item with nothing outstanding gets no extra widget in its
/// tree at all — so the quiet state, which is almost always the state, costs
/// nothing and looks exactly as it did before.
class NavIndicatorBadge extends StatelessWidget {
  const NavIndicatorBadge({
    super.key,
    required this.indicator,
    required this.child,
    this.semanticLabel,
    this.showCount = true,
  });

  final NavIndicator? indicator;
  final Widget child;

  /// What the item is, so a screen reader can say "Registrations, 1 waiting for
  /// a decision" rather than announcing a number attached to nothing.
  final String? semanticLabel;

  /// False for the icon-only rail, where a number inside a 20px dot is
  /// unreadable and a plain dot says the same thing.
  final bool showCount;

  @override
  Widget build(BuildContext context) {
    final current = indicator;
    if (current == null || !current.isVisible) return child;

    final colors = context.colors;
    // From the theme, so both light and dark are already handled — these are
    // the same tokens every status badge in the app reads.
    final background = switch (current.kind) {
      NavIndicatorKind.pendingAction => colors.error,
      NavIndicatorKind.unread => colors.info,
      NavIndicatorKind.warning => colors.warning,
    };

    final description = switch (current.kind) {
      NavIndicatorKind.pendingAction => '${current.count} waiting for a decision',
      NavIndicatorKind.unread => '${current.count} unread',
      NavIndicatorKind.warning => '${current.count} needing attention',
    };

    return Semantics(
      container: true,
      label: semanticLabel == null ? description : '$semanticLabel, $description',
      // The badge is decoration over a label the reader already announces;
      // without this the count is read twice.
      excludeSemantics: true,
      child: Badge(
        // Over about nine the exact number stops being useful and the badge
        // starts to distort the item it is attached to.
        label: showCount ? Text(current.count > 9 ? '9+' : '${current.count}') : null,
        isLabelVisible: showCount,
        backgroundColor: background,
        textColor: colors.onPrimary,
        textStyle: AppTypography.statusBadge.copyWith(
          color: colors.onPrimary,
          fontWeight: FontWeight.w700,
        ),
        // A bare dot needs a size; Flutter's default is tuned for a label.
        smallSize: 8,
        child: child,
      ),
    );
  }
}
