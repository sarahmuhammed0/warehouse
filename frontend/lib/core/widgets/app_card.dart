import 'package:flutter/material.dart';

/// First entry in the shared widget library (architecture §27). Every later
/// feature reuses this instead of hand-rolling its own bordered container.
class AppCard extends StatelessWidget {
  const AppCard({super.key, this.title, required this.child});

  final Widget? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            DefaultTextStyle.merge(
              style: theme.textTheme.titleMedium!,
              child: title!,
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}
