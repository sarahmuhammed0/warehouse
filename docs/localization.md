# Localization &amp; RTL architecture

## Languages (specification §20)

English, Arabic, Kurdish (Badini) — English LTR, the other two RTL.

| Language | Locale used | Direction | ARB file |
|---|---|---|---|
| English | `en` | LTR | `frontend/lib/l10n/app_en.arb` |
| Arabic | `ar` | RTL | `frontend/lib/l10n/app_ar.arb` |
| Kurdish (Badini) | `ku` | RTL | `frontend/lib/l10n/app_ku.arb` |

### ⚠️ Flagged assumption: the Kurdish locale code

Kurdish Badini has no distinct, widely-adopted ISO 639-1 code separate from
generic Kurdish (`ku`). Kurdish is written in **Latin** script in some
regions/dialects (Kurmanji in Turkey/Syria) and **Arabic** script in others
(Sorani in Iraq/Iran, and Badini — also in Iraq — the specific dialect this
project targets). A bare `ku` tag does not by itself say which.

This project uses plain `ku` for the ARB filename and locale code, and
handles the actual RTL behavior explicitly (see below) rather than
depending on any script subtag. **This should be confirmed with a native
Badini speaker/reviewer before real translations ship** — the words in
`app_ku.arb` are a good-faith first pass (standard Kurdish vocabulary in
Arabic script), not a verified professional translation, and the exact
locale/script convention (plain `ku` vs. `Locale.fromSubtags(languageCode:
'ku', scriptCode: 'Arab')`) is a reasonable default, not a settled fact.

## Why strings are localizable now, business terms mostly aren't yet

Every string the Phase 1 shell displays — nav labels, common actions
(search/filters/retry/cancel), empty/error state defaults, pagination
labels, the module-coming-soon message — is in `lib/l10n/app_*.arb` and
reached only through `AppLocalizations.of(context)!`, never a hard-coded
English literal. That's the architecture requirement (§20: "the
architecture must allow all future UI strings to be localized instead of
hardcoded") and it's true today, not aspirational.

What's *not* translated: business vocabulary that doesn't exist as a
concept in the app yet — order statuses (`BusinessStatus` in
`shared/badges/status_badge.dart` renders English words like "Pending",
"Completed"), product field names, report titles. Translating those before
the modules that use them exist risks inventing terminology a later
business decision (or a native reviewer) would then have to unwind — see
the ground rule against inventing requirements. When Phase 2+ builds a
module, its screen adds its own ARB keys the same way the shell's did.

## RTL approach

**Not** handled via Flutter's built-in per-language RTL table alone —
that table doesn't reliably know a bare `ku` tag is RTL (see the flagged
assumption above), so direction is resolved explicitly:

```dart
// lib/localization/app_locales.dart
static bool isRtlLocale(Locale locale) { ... } // ar, ku → true; else false
static TextDirection directionFor(Locale locale) => ...

// lib/app.dart — MaterialApp.router's `builder`
final resolvedLocale = Localizations.localeOf(context);
final direction = AppLocales.directionFor(resolvedLocale);
return Directionality(textDirection: direction, child: child);
```

This wraps the *entire* app in one explicit `Directionality`, computed once
per locale change — every descendant widget inherits it automatically.
Nothing below `app.dart` sets its own `TextDirection`.

### What "reusable RTL-aware patterns" meant in practice (§21)

- **Layout mirroring is automatic** for anything built from `Row`,
  `MainAxisAlignment`, `Padding` with `EdgeInsetsDirectional`, and
  `Alignment` via `AlignmentDirectional` — Flutter mirrors all of these
  from the ambient `Directionality` with zero extra code. The sidebar
  (`AppSidebar`, a `Row` in `AppShell`) and the overlay side panel
  (`AlignmentDirectional.centerEnd` + `BorderRadiusDirectional.horizontal`
  in `shared/overlays/app_overlay_panel.dart`) both flip sides correctly in
  RTL for this reason, not because of manual per-widget RTL logic.
- **Literal directional glyphs are not automatic** — `Icons.chevron_left`/
  `chevron_right`/`first_page`/`last_page` are fixed glyphs, not mirrored by
  `Directionality`. Every place this app uses one (`AppSidebar`'s collapse
  toggle, `PaginationBar`'s prev/next/first/last) explicitly checks
  `Directionality.of(context)` and swaps the icon — see the comments at
  those call sites for the exact reasoning. This is the one place RTL
  needed a manual decision rather than falling out of the framework.
- **Text alignment** follows `Directionality` automatically for `Text` and
  form fields (Flutter's default `TextAlign.start`), so labels, helper
  text, and table cell content never needed explicit RTL handling.

### Update (Phase 1.5): Kurdish needed a framework-localization fallback

Once the localization foundation was actually exercised by a real,
executable test (Phase 1.5, after the Flutter toolchain was repaired — see
`docs/toolchain-fix.md`), it surfaced a genuine gap: Flutter's own built-in
`MaterialLocalizations`/`CupertinoLocalizations` don't have a Kurdish
translation set, so the app crashed under the `ku` locale. Fixed via
`lib/localization/kurdish_localizations_fallback.dart` — two delegates
that claim `ku` support and serve Arabic's translations for generic
framework chrome only, registered ahead of the standard delegates in
`app.dart`. `lib/l10n/app_ku.arb` (this project's own Kurdish strings) is
unaffected and unchanged by this.

### Verifying RTL (§29/§31)

`features/settings/settings_screen.dart`'s "Appearance (foundation
preview)" section includes a locale switcher (English/Arabic/Kurdish/
System) specifically so RTL can be exercised by using the running app —
switch to Arabic or Kurdish and confirm the sidebar moves to the right,
the pagination/collapse chevrons point the correct way, and breadcrumbs/
forms read right-to-left. See the root `README.md`'s testing section for
what was and wasn't possible to verify in this environment.
