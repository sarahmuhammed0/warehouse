import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../layout/responsive/app_breakpoints.dart';

/// Bottom sheet (mobile) / side panel (desktop, tablet) — one call site for
/// both, per §19: "must adapt between desktop/tablet/mobile." Used for
/// filters, record details, and quick actions once a future module needs
/// them; on a phone a right-hand side panel would be unusably narrow, so
/// this switches to a bottom sheet instead of shrinking the same layout.
Future<T?> showAppOverlayPanel<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double panelWidth = 420,
}) {
  final isMobile = MediaQuery.sizeOf(context).width < AppBreakpoints.mobile;

  if (isMobile) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => builder(context),
      ),
    );
  }

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.3),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) => Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Material(
        color: context.colors.surface,
        borderRadius: const BorderRadiusDirectional.horizontal(start: Radius.circular(AppRadius.lg)),
        child: SizedBox(
          width: panelWidth,
          height: double.infinity,
          child: SafeArea(child: builder(context)),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      );
    },
  );
}
