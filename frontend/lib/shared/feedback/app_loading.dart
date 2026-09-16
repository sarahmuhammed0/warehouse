import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Three loading treatments (§15) — picked by where the loading happens,
/// not by developer preference, so the same situation always looks the
/// same across every future module:
///  - [AppLoading.page] — nothing useful is on screen yet.
///  - [AppLoading.section] — one card/panel within an otherwise-usable page.
///  - a button's own `loading` flag (see `AppButton`) covers the third case.
class AppLoading extends StatelessWidget {
  const AppLoading._({required this.size});

  factory AppLoading.page() => const AppLoading._(size: 28);
  factory AppLoading.section() => const AppLoading._(size: 20);

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(strokeWidth: 2.5, color: context.colors.primary),
      ),
    );
  }
}
