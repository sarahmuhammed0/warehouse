import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../cards/app_card.dart';
import '../feedback/app_empty_state.dart';

/// A titled content region on the dashboard (§16) — the container other,
/// more specific dashboard cards below build on for their outer chrome.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, this.actions, required this.child});

  final String title;
  final List<Widget>? actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(title: Text(title), actions: actions, child: child);
  }
}

/// One row of a recent-activity feed (§16/§25 "Recent activity"). Generic
/// over what an "entry" is — a future module supplies real items; Phase 1
/// only proves the shape (see `DashboardPlaceholderScreen`).
class ActivityListEntry {
  const ActivityListEntry({required this.title, required this.timestamp, this.icon});
  final String title;
  final String timestamp;
  final IconData? icon;
}

class ActivityListCard extends StatelessWidget {
  const ActivityListCard({
    super.key,
    required this.title,
    required this.entries,
    this.emptyLabel = 'No recent activity',
  });

  final String title;
  final List<ActivityListEntry> entries;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SectionCard(
      title: title,
      child: entries.isEmpty
          ? AppEmptyState(icon: Icons.history, title: emptyLabel)
          : Column(
              children: [
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(entry.icon ?? Icons.circle, size: 8, color: colors.textMuted),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            entry.title,
                            style: AppTypography.body.copyWith(color: colors.textPrimary),
                          ),
                        ),
                        Text(entry.timestamp, style: AppTypography.caption.copyWith(color: colors.textMuted)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// A single alert line (low stock, pending payment, etc. — §16/§20's
/// notification categories surfaced on the dashboard itself, not only the
/// bell icon).
class AlertCardEntry {
  const AlertCardEntry({required this.message, this.icon = Icons.warning_amber_outlined});
  final String message;
  final IconData icon;
}

class AlertCard extends StatelessWidget {
  const AlertCard({super.key, required this.title, required this.alerts, this.emptyLabel = 'No alerts'});

  final String title;
  final List<AlertCardEntry> alerts;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SectionCard(
      title: title,
      child: alerts.isEmpty
          ? AppEmptyState(icon: Icons.check_circle_outline, title: emptyLabel)
          : Column(
              children: [
                for (final alert in alerts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(alert.icon, size: 18, color: colors.warning),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(alert.message, style: AppTypography.body.copyWith(color: colors.textPrimary)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
