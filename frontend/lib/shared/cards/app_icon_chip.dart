import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_typography.dart';

/// The pale rounded square an icon sits in — the single most repeated
/// detail in the FactoryOS visual language. It appears on every stat card,
/// every card header and every alert row, so it lives here once rather
/// than as a hand-built `Container` with a `withValues(alpha: 0.12)` in
/// each of them.
///
/// [tone] tints the chip for a status-bearing icon (a warning, an error).
/// Left null it uses the brand accent, which is the right answer for the
/// large majority of cases — §11's "do not overdecorate".
class AppIconChip extends StatelessWidget {
  const AppIconChip({
    super.key,
    required this.icon,
    this.tone,
    this.size = 42,
    this.iconSize = 20,
  });

  final IconData icon;
  final Color? tone;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = tone ?? colors.primary;
    // The brand accent has a dedicated token for its own pale backing;
    // a status tone derives one, since there is no separate "warningChip"
    // color and inventing four more tokens for it would be noise.
    final background = tone == null ? colors.accentSoft : accent.withValues(alpha: 0.13);

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, borderRadius: AppRadius.smRadius),
      child: Icon(icon, size: iconSize, color: accent),
    );
  }
}

/// The small circular control that sits at the top-right of a card — the
/// "open this in full" arrow in the reference design, and the shell's
/// search/notification buttons.
///
/// Outlined rather than filled: it is a secondary affordance next to the
/// card's own content, and a filled circle here would compete with the
/// primary action on the page.
class AppCircleButton extends StatelessWidget {
  const AppCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 34,
    this.iconSize = 17,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;

  /// Fills with the brand accent — for the one circular control on a
  /// surface that *is* the primary action.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final disabled = onPressed == null;
    final foreground = disabled
        ? colors.disabled
        : filled
            ? colors.onPrimary
            : colors.textSecondary;

    final button = Material(
      color: filled ? colors.primary : Colors.transparent,
      shape: CircleBorder(
        side: filled ? BorderSide.none : BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: iconSize, color: foreground),
        ),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// A circular initials avatar — a person, a business, a counterparty on an
/// order row. Colored from the text it shows rather than at random, so the
/// same name always lands on the same color and a list of rows stays
/// recognisable between visits.
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, required this.label, this.size = 34, this.tone});

  final String label;
  final double size;

  /// Overrides the derived color — for an avatar that has a real semantic
  /// color already (e.g. the signed-in user, always on brand).
  final Color? tone;

  /// Up to two letters: initials for "Karwan Co." → "KC", a single letter
  /// for a one-word name.
  static String initialsOf(String value) {
    final words = value.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return (w.length == 1 ? w : w.substring(0, 2)).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // A fixed, deliberately small palette drawn from the app's own
    // semantic colors — not arbitrary hues, so a table of avatars still
    // reads as one product.
    final palette = [colors.primary, colors.secondary, colors.success, colors.warning, colors.info];
    final accent = tone ?? palette[label.hashCode.abs() % palette.length];

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: Text(
        initialsOf(label),
        style: AppTypography.statusBadge.copyWith(
          color: accent,
          fontSize: size * 0.34,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
