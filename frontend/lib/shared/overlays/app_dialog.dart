import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../layout/responsive/app_breakpoints.dart';

/// The one dialog every future module uses for forms/details/quick actions
/// (§19). Adapts by breakpoint rather than being one fixed size everywhere:
/// desktop/tablet gets a centered, width-capped dialog; mobile gets a
/// near-full-screen sheet, since a 400px-wide phone dialog with its own
/// internal margins leaves almost nothing to work with otherwise.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 560,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => _ResponsiveDialogShell(maxWidth: maxWidth, child: builder(context)),
  );
}

class _ResponsiveDialogShell extends StatelessWidget {
  const _ResponsiveDialogShell({required this.maxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < AppBreakpoints.mobile;

    if (isMobile) {
      return Dialog.fullscreen(child: child);
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lgRadius),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: child,
      ),
    );
  }
}
