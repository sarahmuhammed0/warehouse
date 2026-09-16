import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_typography.dart';

/// The semantic color *group* a status belongs to — separate from any
/// single business status name, so the badge widget itself never needs to
/// know about orders/returns/payments. Kept distinct from the brand accent
/// per the design-system rule that status color and accent color are never
/// the same channel.
enum StatusTone { success, warning, danger, info, neutral }

/// Every status word the specification uses across orders, returns,
/// payments, and production (§14/§16/§22/§24/§34 25). The color/label
/// mapping lives once, here — no future module re-derives "what color is
/// Cancelled" on its own. Business logic that decides *when* a record
/// enters one of these states is explicitly out of scope for Phase 1.
enum BusinessStatus {
  active,
  inactive,
  draft,
  pending,
  confirmed,
  processing,
  ready,
  completed,
  cancelled,
  returned,
  partiallyReturned,
  paid,
  partiallyPaid,
  unpaid,
  requested,
  approved,
  rejected,
  planned,
  inProgress,
}

class _StatusConfig {
  const _StatusConfig(this.label, this.tone);
  final String label;
  final StatusTone tone;
}

const Map<BusinessStatus, _StatusConfig> _statusConfig = {
  BusinessStatus.active: _StatusConfig('Active', StatusTone.success),
  BusinessStatus.inactive: _StatusConfig('Inactive', StatusTone.neutral),
  BusinessStatus.draft: _StatusConfig('Draft', StatusTone.neutral),
  BusinessStatus.pending: _StatusConfig('Pending', StatusTone.warning),
  BusinessStatus.confirmed: _StatusConfig('Confirmed', StatusTone.info),
  BusinessStatus.processing: _StatusConfig('Processing', StatusTone.info),
  BusinessStatus.ready: _StatusConfig('Ready', StatusTone.info),
  BusinessStatus.completed: _StatusConfig('Completed', StatusTone.success),
  BusinessStatus.cancelled: _StatusConfig('Cancelled', StatusTone.danger),
  BusinessStatus.returned: _StatusConfig('Returned', StatusTone.warning),
  BusinessStatus.partiallyReturned: _StatusConfig('Partially Returned', StatusTone.warning),
  BusinessStatus.paid: _StatusConfig('Paid', StatusTone.success),
  BusinessStatus.partiallyPaid: _StatusConfig('Partially Paid', StatusTone.warning),
  BusinessStatus.unpaid: _StatusConfig('Unpaid', StatusTone.danger),
  BusinessStatus.requested: _StatusConfig('Requested', StatusTone.neutral),
  BusinessStatus.approved: _StatusConfig('Approved', StatusTone.success),
  BusinessStatus.rejected: _StatusConfig('Rejected', StatusTone.danger),
  BusinessStatus.planned: _StatusConfig('Planned', StatusTone.neutral),
  BusinessStatus.inProgress: _StatusConfig('In Progress', StatusTone.info),
};

/// Generic status pill. Two ways to use it:
///  - `StatusBadge.forStatus(BusinessStatus.pending)` — the catalog above.
///  - `StatusBadge(label: 'Checking…', tone: StatusTone.neutral)` — for
///    anything not yet in the catalog (Phase 0's health-check screen uses
///    this form).
///
/// Never communicates status by color alone (§22 accessibility): the label
/// text is always shown, color is reinforcement, not the only signal.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.tone});

  factory StatusBadge.forStatus(BusinessStatus status) {
    final config = _statusConfig[status]!;
    return StatusBadge(label: config.label, tone: config.tone);
  }

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (fg, bg) = switch (tone) {
      StatusTone.success => (colors.success, colors.successBg),
      StatusTone.warning => (colors.warning, colors.warningBg),
      StatusTone.danger => (colors.error, colors.errorBg),
      StatusTone.info => (colors.info, colors.infoBg),
      StatusTone.neutral => (colors.textSecondary, colors.disabledBg),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.pillRadius),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.statusBadge.copyWith(color: fg),
      ),
    );
  }
}
