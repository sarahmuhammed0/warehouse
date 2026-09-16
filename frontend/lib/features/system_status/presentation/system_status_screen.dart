import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../shared/badges/status_badge.dart';
import '../../../shared/cards/app_card.dart';
import '../../../shared/layout/responsive/responsive_layout.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_typography.dart';
import 'providers/health_providers.dart';

/// Retained from Phase 0 as a dev utility (not a business screen, not in
/// the main nav — see `routing/app_routes.dart`'s comment). It proves the
/// full chain (Flutter → API layer → Express → MySQL) still works end to
/// end after Phase 1's restructuring, with real requests, no mocked data.
class SystemStatusScreen extends StatelessWidget {
  const SystemStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System status (dev utility)')),
      body: ResponsiveLayout(
        mobile: (context) => const _StatusBody(maxWidth: double.infinity),
        desktop: (context) => const Center(child: _StatusBody(maxWidth: 640)),
      ),
    );
  }
}

class _StatusBody extends ConsumerWidget {
  const _StatusBody({required this.maxWidth});

  final double maxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.lg,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('System status', style: AppTypography.pageTitle.copyWith(color: colors.textPrimary)),
                    Text(
                      'Live checks against the real backend and database — no mock data.',
                      style: AppTypography.caption.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
                OutlinedButton(
                  onPressed: () {
                    ref.invalidate(apiHealthProvider);
                    ref.invalidate(databaseHealthProvider);
                  },
                  child: const Text('Recheck'),
                ),
              ],
            ),
            const _ApiHealthCard(),
            const _DatabaseHealthCard(),
          ],
        ),
      ),
    );
  }
}

class _ApiHealthCard extends ConsumerWidget {
  const _ApiHealthCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(apiHealthProvider);

    return AppCard(
      title: Row(
        spacing: AppSpacing.sm,
        children: [
          const Text('Backend API'),
          health.when(
            data: (_) => StatusBadge(label: 'OK', tone: StatusTone.success),
            loading: () => StatusBadge(label: 'Checking', tone: StatusTone.neutral),
            error: (_, _) => StatusBadge(label: 'Unreachable', tone: StatusTone.danger),
          ),
        ],
      ),
      child: health.when(
        data: (data) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoRow('Status', data.status),
            _InfoRow('Environment', data.environment),
            _InfoRow('Uptime', '${data.uptimeSeconds}s'),
          ],
        ),
        loading: () => const Text('Checking…'),
        error: (error, _) => Text(
          error is Failure ? error.message : 'Unexpected error.',
          style: TextStyle(color: context.colors.error),
        ),
      ),
    );
  }
}

class _DatabaseHealthCard extends ConsumerWidget {
  const _DatabaseHealthCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(databaseHealthProvider);

    return AppCard(
      title: Row(
        spacing: AppSpacing.sm,
        children: [
          const Text('Database (MySQL)'),
          health.when(
            data: (_) => StatusBadge(label: 'OK', tone: StatusTone.success),
            loading: () => StatusBadge(label: 'Checking', tone: StatusTone.neutral),
            error: (_, _) => StatusBadge(label: 'Unreachable', tone: StatusTone.danger),
          ),
        ],
      ),
      child: health.when(
        data: (data) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoRow('Engine', data.engine),
            _InfoRow('Version', data.version),
            _InfoRow('Host', '${data.host}:${data.port}'),
            _InfoRow('Database', data.database),
          ],
        ),
        loading: () => const Text('Checking…'),
        error: (error, _) => Text(
          error is Failure
              ? '${error.message} — see docs/environment.md for how to start it.'
              : 'Unexpected error.',
          style: TextStyle(color: context.colors.error),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.body.copyWith(color: colors.textSecondary)),
          Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: colors.textPrimary)),
        ],
      ),
    );
  }
}
