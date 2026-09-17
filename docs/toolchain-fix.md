# Flutter toolchain fix — Phase 1.5

## Root cause (confirmed, not guessed)

`material_ui` and `cupertino_ui` are **independently-versioned pub.dev
packages** that the `flutter` SDK package's Material/Cupertino widgets are
built on. They are published on their own release cadence — faster than
Flutter stable releases — and are **not** version-pinned by
`packages/flutter/pubspec.yaml` inside this installed Flutter SDK
(confirmed by reading that file directly: it declares `meta: 1.18.0` and
four other packages, but no `material_ui`/`cupertino_ui` entry — see
below for how they resolve regardless). A plain `flutter pub get` in any
downstream project resolves them to their **latest published versions**
(`material_ui 1.3.0`, `cupertino_ui 1.1.0` at the time of Phase 0/1).

Those latest versions use a `@awaitNotRequired` annotation newly added to
several async framework methods (`route.dart`, `dialog.dart`,
`date_picker.dart`, `bottom_sheet.dart`, `popup_menu.dart`,
`time_picker.dart`, `carousel.dart`). That annotation is exported through
`package:flutter/foundation.dart` — but **this specific installed Flutter
SDK build** (stable, commit `559ffa3f75`, 2026-05-15) predates the
framework-side change that re-exports it, so the exported name doesn't
exist where `material_ui`/`cupertino_ui` expect it, and the Dart compiler
(CFE) reports it as undefined.

This is a genuine, currently-tracked upstream issue in the Flutter/pub
ecosystem — confirmed via
[flutter/packages#12622](https://github.com/flutter/packages/pull/12622)
("[material_ui] Add awaitNotRequired annotation to material_ui"), which is
the fix landing upstream for the *other* side of this same mismatch. It is
not something introduced by this project's code or dependency choices —
`flutter_riverpod`, `go_router`, `dio`, and `flutter_localizations` play no
part in it.

## What was ruled out first (with evidence, not assumption)

| Hypothesis | Check performed | Result |
|---|---|---|
| Project code causing it | `flutter analyze`: 0 issues in both Phase 0 and Phase 1 | Ruled out — analyzer is fully clean |
| `meta` package too old / missing the symbol | Read `meta-1.18.0/lib/meta.dart` directly — `awaitNotRequired` is a plain `const` declared at line 92 | Ruled out — the symbol genuinely exists in the resolved `meta` version |
| Stale/corrupted Flutter engine cache | `flutter precache --force` (re-downloaded `flutter_patched_sdk`, `flutter_patched_sdk_product`, and all other cached artifacts) + `flutter clean` + fresh `pub get`, then re-ran `flutter test` | Ruled out — identical failure persisted after a full cache rebuild |
| Wrong/conflicting SDK on PATH | `where flutter`, `where dart`, `$env:PATH` inspection | A standalone Dart SDK (`C:\dartsdk-windows-x64-release`) and a duplicated, nested Flutter checkout (`C:\flutter_windows_3.44.0-stable\flutter\flutter\`) both exist — see "Environment hygiene notes" below — but both Flutter checkouts are the **identical git commit** (`559ffa3f75e7402d65a8def9c28389a9b2e6fe42`) with identical bundled Dart SDK version (3.12.0), so this duplication is not what caused the compile error |
| Version skew between `material_ui`/`cupertino_ui` and this Flutter build | Read `packages/flutter/pubspec.yaml` (no pin on these two packages) + web search confirming the known upstream issue and its fix PR | **Confirmed as the actual root cause** |

## Fix applied

`frontend/pubspec.yaml` — added `dependency_overrides` pinning both
packages to the last versions published **before** the `awaitNotRequired`
annotation was introduced, which this Flutter SDK build's framework source
is fully compatible with:

```yaml
dependency_overrides:
  material_ui: "<1.3.0"   # resolves to 1.2.0
  cupertino_ui: "<1.1.0"  # resolves to 1.0.2
```

This is a **project-level, reversible, two-line change** — no Flutter SDK
reinstall, no version upgrade/downgrade of the SDK itself, no change to
`flutter_riverpod`/`go_router`/`dio`/`flutter_localizations`/any other
dependency this project actually added. `flutter pub get` confirms only
`cupertino_ui` and `material_ui` changed, plus `flutter_lints` moved from a
direct to a transitive dependency as an artifact of the override
resolution (its version, `6.0.0`, is unchanged).

**Why this over upgrading the Flutter SDK:** an SDK upgrade is a
machine-level change with a much larger blast radius (affects every
Flutter project on this machine, requires re-validating the entire
toolchain, and per the task's own instructions needs explicit confirmation
before being executed). Pinning two transitive packages to their
last-known-good versions is fully contained to this project, immediately
verifiable, and trivially reversible (delete four lines) — the least
invasive fix that produces a supported, internally-consistent result:
Flutter framework source, `material_ui`, and `cupertino_ui` are now three
mutually-compatible versions, not three independently-drifting ones.

**When to remove this override:** once this machine's Flutter SDK is
upgraded past the commit that added the `awaitNotRequired` re-export in
`foundation.dart` (or once `flutter/packages#12622` ships and a
correspondingly-compatible `material_ui`/`cupertino_ui` pair is available
for the installed Flutter version), this override becomes unnecessary and
should be deleted so the project tracks upstream latest again.

**Verified, not just applied:** `flutter clean` + fresh `pub get` +
`flutter analyze` (0 issues) + `flutter test` (19/19 passing) + `flutter
build web --release` (succeeds) + `flutter run -d web-server` (compiles,
serves, responds to a real HTTP request) — all re-run from a clean state
after the fix, not just once.

## A second, genuine finding from the RTL verification tests

Writing real tests that actually run (rather than only being written, as
in Phase 1) immediately caught a real gap: Flutter's built-in
`GlobalMaterialLocalizations`/`GlobalCupertinoLocalizations` delegates
don't ship translations for Kurdish (`ku`) — it isn't one of the ~100
languages Flutter itself has translated framework strings into. Declaring
`ku` as a supported locale without accounting for this is unsafe: the
moment the resolved locale was `ku`, any Material widget reading
`MaterialLocalizations.of(context)` (most of them, including ones with no
visible framework text) threw `No MaterialLocalizations found` and crashed
the tree — caught by the new
`App builds under the ku locale with correct Directionality` test.

**Fix:** `frontend/lib/localization/kurdish_localizations_fallback.dart` —
two small `LocalizationsDelegate`s that claim support for `ku` and hand
back Arabic's translations for framework-level chrome (also RTL, so layout
direction is unaffected), registered ahead of the standard delegates in
`app.dart`. This only affects generic framework strings (e.g. a date
picker's "OK"/"Cancel"); every app-specific string
(`lib/l10n/app_ku.arb`, via `AppLocalizations.of(context)`) still renders
in actual Kurdish. This is Flutter's own documented pattern for a locale
outside its built-in translated set, not a workaround.

This is a genuine Phase 1 code fix, in scope per this phase's own
instructions ("if a test fails because of an actual Phase 1 code problem:
diagnose it, fix only the relevant Phase 1 code") — not a database, business
logic, or toolchain change.

## Environment hygiene notes (observed, not fixed — out of scope for this task)

Two things were found during diagnosis that are **not** the root cause of
this bug and were **not** touched, since fixing them wasn't necessary to
resolve the actual problem and doing so would be a larger, riskier
machine-level change than this task called for:

1. **A standalone Dart SDK** (`C:\dartsdk-windows-x64-release`) sits ahead
   of Flutter's own bundled Dart SDK on `PATH`. Running the bare `dart`
   command (outside of `flutter <command>`, which resolves its own bundled
   Dart internally regardless of `PATH`) uses this standalone copy. It
   happens to also be version 3.12.0, so it caused no observed problems
   here, but it's worth knowing about if a future `dart`-only command
   behaves unexpectedly.
2. **A duplicated, nested Flutter checkout**:
   `C:\flutter_windows_3.44.0-stable\flutter\flutter\` is a second,
   complete Flutter SDK git clone living inside the first one
   (`C:\flutter_windows_3.44.0-stable\flutter\`). Both are the identical
   commit, so this caused no version-skew problems for this task, but it
   is wasted disk space and a plausible source of confusion for a future
   `flutter upgrade` (it's not obvious which of the two `PATH` would favor
   after an upgrade, since only the outer one is first in `PATH` today).
   Recommend removing the inner `flutter\flutter\` directory as routine
   cleanup — **not done here**, flagged for your decision since deleting
   a multi-GB SDK checkout is exactly the kind of destructive,
   easily-deferred action this task's own ground rules ask to avoid doing
   unprompted.
