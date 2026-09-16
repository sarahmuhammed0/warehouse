import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/responsive/responsive_layout.dart';
import '../../../core/widgets/status_badge.dart';
import 'providers/health_providers.dart';

/// Phase 0's one screen. Deliberately not a business screen — it exists to
/// prove the full chain (Flutter → API layer → Express → MySQL) works end
/// to end with real requests, no mocked data. It's also the first screen
/// built on [ResponsiveLayout], so the pattern is proven before dozens of
/// business screens are built on top of it.
class SystemStatusScreen extends StatelessWidget {
  const SystemStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Warehouse OS'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Phase 0 — Project Foundation',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
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
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('System status', style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      'Live checks against the real backend and database — no mock data.',
                      style: Theme.of(context).textTheme.bodySmall,
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
        spacing: 8,
        children: [
          const Text('Backend API'),
          StatusBadge(
            status: health.when(
              data: (_) => AppStatus.ok,
              loading: () => AppStatus.checking,
              error: (_, _) => AppStatus.error,
            ),
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
          style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        spacing: 8,
        children: [
          const Text('Database (MySQL)'),
          StatusBadge(
            status: health.when(
              data: (_) => AppStatus.ok,
              loading: () => AppStatus.checking,
              error: (_, _) => AppStatus.error,
            ),
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
          style: TextStyle(color: Theme.of(context).colorScheme.error),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
          Text(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ],
      ),
    );
  }
}
