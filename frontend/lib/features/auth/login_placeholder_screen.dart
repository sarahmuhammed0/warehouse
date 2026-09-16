import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// A public route (§23), deliberately outside both shells — no sidebar, no
/// business/admin nav. No authentication logic exists yet (§27): this is
/// the placeholder Phase 2's real login screen replaces, kept here only so
/// `AppRoutes.login` resolves to something and the public/business/admin
/// route separation is real, not just planned.
class LoginPlaceholderScreen extends StatelessWidget {
  const LoginPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 40, color: colors.textMuted),
              const SizedBox(height: AppSpacing.md),
              Text('Sign in is coming in a later phase', style: AppTypography.sectionTitle.copyWith(color: colors.textPrimary)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Phone-number + password authentication connects to the backend in Phase 2.',
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
