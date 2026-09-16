import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'form_field_wrapper.dart';

enum UploadKind { image, file }

/// Upload placeholder (§12) — the dashed drop-zone shape a real upload
/// (product images, category images, business logo, PDF/document
/// attachments — §8/§28's image/file fields) will use once a module needs
/// actual file picking + upload to the backend. `onTap` is provided so a
/// future module can wire `file_picker`/`image_picker` without this widget
/// changing shape; Phase 1 does not add either dependency (§26 — no feature
/// needs it yet).
class UploadPlaceholder extends StatelessWidget {
  const UploadPlaceholder({
    super.key,
    required this.label,
    this.kind = UploadKind.image,
    this.required = false,
    this.fileName,
    this.onTap,
  });

  final String label;
  final UploadKind kind;
  final bool required;
  final String? fileName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return FormFieldWrapper(
      label: label,
      required: required,
      child: InkWell(
        borderRadius: AppRadius.mdRadius,
        onTap: onTap,
        child: DottedBorderBox(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  kind == UploadKind.image ? Icons.image_outlined : Icons.upload_file_outlined,
                  size: 28,
                  color: colors.textMuted,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  fileName ?? (kind == UploadKind.image ? 'Click to upload an image' : 'Click to upload a file'),
                  style: AppTypography.body.copyWith(color: fileName != null ? colors.textPrimary : colors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain dashed-edge container — `CustomPaint` rather than a new
/// dependency, since this is the only place the app needs a dashed border.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: context.colors.border),
      child: Center(child: child),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(AppRadius.md));
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      const dashLength = 6.0, gapLength = 4.0;
      while (distance < metric.length) {
        final next = distance + dashLength;
        canvas.drawPath(metric.extractPath(distance, next.clamp(0, metric.length)), paint);
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => oldDelegate.color != color;
}
