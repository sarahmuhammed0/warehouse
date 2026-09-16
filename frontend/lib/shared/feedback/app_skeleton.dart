import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';

/// Skeleton loading primitives (§15/§41). A shimmering placeholder shaped
/// like the content that's about to appear reads as "this is loading" far
/// faster than a spinner for list/table-shaped content — that's the whole
/// reason skeletons exist, so these are deliberately shape primitives
/// (`line`, `block`) that a feature composes into its own skeleton layout,
/// not one fixed "skeleton screen."
class AppSkeleton extends StatefulWidget {
  const AppSkeleton.line({super.key, this.width, this.height = 14})
    : shape = BoxShape.rectangle,
      radius = null;

  const AppSkeleton.block({super.key, this.width, this.height = 80, this.radius})
    : shape = BoxShape.rectangle;

  const AppSkeleton.circle({super.key, required double size})
    : width = size,
      height = size,
      shape = BoxShape.circle,
      radius = null;

  final double? width;
  final double height;
  final BoxShape shape;
  final BorderRadius? radius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = context.colors.disabledBg;
    final highlight = context.colors.border;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(base, highlight, t),
            shape: widget.shape,
            borderRadius: widget.shape == BoxShape.rectangle
                ? (widget.radius ?? AppRadius.smRadius)
                : null,
          ),
        );
      },
    );
  }
}

/// A ready-made skeleton for one table/list row — the most common shape
/// this app needs (§11's data table foundation), so a future module
/// doesn't hand-compose lines for every list it builds.
class AppSkeletonRow extends StatelessWidget {
  const AppSkeletonRow({super.key, this.columns = 4});

  final int columns;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: List.generate(columns, (i) {
          return Expanded(
            flex: i == 0 ? 2 : 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: const AppSkeleton.line(),
            ),
          );
        }),
      ),
    );
  }
}
