import '../../l10n/generated/app_localizations.dart';
import 'app_mode.dart';

/// "Showing local demo data — not connected to a live backend yet."
///
/// True in demo mode, and a plain falsehood in backend mode — where the rows
/// on screen came from MySQL over HTTP. It was hardcoded into both dashboard
/// headers and six empty states, so the app told every backend-mode user that
/// nothing they were looking at was real.
///
/// Returns null when there is nothing truthful to say, which every caller
/// already handles: `PageScaffold.subtitle`, `AppEmptyState.description` and
/// `AppDataTable.emptyDescription` are all nullable and simply omit the line.
///
/// An empty list in backend mode needs no explanation anyway — it means the
/// business has no rows yet, which is what an empty table already says.
String? dataSourceNotice(AppLocalizations l10n) {
  return switch (AppModeConfig.mode) {
    AppMode.demo => l10n.demoDataNotice,
    AppMode.backend => null,
  };
}
