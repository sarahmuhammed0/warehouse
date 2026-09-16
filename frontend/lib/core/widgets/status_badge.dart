import 'package:flutter/material.dart';

enum AppStatus { checking, ok, error }

/// Generic status pill — the same widget every later module's order/return/
/// production status badge (architecture §27, §42/§43) will reuse; Phase 0
/// only needs three states.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final AppStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    late final Color bg;
    late final Color fg;
    late final String label;

    switch (status) {
      case AppStatus.checking:
        bg = scheme.surfaceContainerHighest;
        fg = scheme.onSurfaceVariant;
        label = 'CHECKING…';
      case AppStatus.ok:
        bg = scheme.tertiaryContainer;
        fg = scheme.onTertiaryContainer;
        label = 'OK';
      case AppStatus.error:
        bg = scheme.errorContainer;
        fg = scheme.onErrorContainer;
        label = 'UNREACHABLE';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
