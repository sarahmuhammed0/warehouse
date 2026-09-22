import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../cards/app_card.dart';
import '../cards/app_icon_chip.dart';
import '../feedback/app_empty_state.dart';

/// A titled content region on the dashboard (§16) — the container other,
/// more specific dashboard cards below build on for their outer chrome.
///
/// [subtitle] and [leading] are the reference's card-header anatomy
/// (`[icon] Title / muted description ... [action]`); both are optional so
/// an existing caller that passes only a title is unchanged.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    required this.child,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget>? actions;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      leading: icon == null ? null : AppIconChip(icon: icon!, size: 38, iconSize: 18),
      actions: actions,
      padding: padding,
      child: child,
    );
  }
}

/// One row of a recent-activity feed (§16/§25 "Recent activity").
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
    this.subtitle,
    this.actions,
    this.emptyLabel = 'No recent activity',
  });

  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final List<ActivityListEntry> entries;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SectionCard(
      title: title,
      subtitle: subtitle,
      actions: actions,
      child: entries.isEmpty
          ? AppEmptyState(icon: Icons.history, title: emptyLabel)
          : Column(
              children: [
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Row(
                      children: [
                        _ActivityDot(color: colors.primary),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            entry.title,
                            style: AppTypography.body.copyWith(color: colors.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (entry.timestamp.isNotEmpty) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            entry.timestamp,
                            style: AppTypography.caption.copyWith(color: colors.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The small ring-and-dot bullet that leads an activity row — quieter than
/// a filled dot at the same size, which reads as a bullet point rather
/// than as a status light.
class _ActivityDot extends StatelessWidget {
  const _ActivityDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
                        const SizedBox(width: AppSpacing.md),
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

/// A tappable list row inside a card — an alert, a drill-down, a summary
/// line. Rows are separated by whitespace and a hover tint rather than by
/// rules (§12: "avoid visually heavy grid lines, use whitespace instead").
class CardListRow extends StatelessWidget {
  const CardListRow({
    super.key,
    required this.label,
    this.icon,
    this.iconSize = 18,
    this.tone,
    this.trailingText,
    this.trailingColor,
    this.trailingStrong = true,
    this.onTap,
  });

  final String label;
  final IconData? icon;

  /// Small for a bullet (an activity dot), full size for a meaningful
  /// glyph (an alert's own icon).
  final double iconSize;

  final Color? tone;
  final String? trailingText;
  final Color? trailingColor;

  /// A count reads as a figure and is set strong; a timestamp is metadata
  /// and is not.
  final bool trailingStrong;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.smRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.md),
          child: Row(
            children: [
              if (icon != null) ...[
                SizedBox(
                  width: 18,
                  child: Center(
                    child: Icon(icon, size: iconSize, color: tone ?? colors.textSecondary),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.body.copyWith(color: colors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailingText != null)
                Text(
                  trailingText!,
                  style: (trailingStrong ? AppTypography.bodyStrong : AppTypography.caption)
                      .copyWith(color: trailingColor ?? colors.textPrimary),
                ),
              if (onTap != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  // A literal glyph Flutter does not auto-mirror (§21).
                  isRtl ? Icons.chevron_left : Icons.chevron_right,
                  size: 18,
                  color: colors.textMuted,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
