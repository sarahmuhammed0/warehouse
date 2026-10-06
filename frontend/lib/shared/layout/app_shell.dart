import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/providers/auth_controller.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_elevation.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/theme_controller.dart';
import '../navigation/app_rail.dart';
import '../navigation/nav_activity_provider.dart';
import '../navigation/app_sidebar.dart';
import '../navigation/app_topbar.dart';
import '../navigation/nav_items.dart';
import 'responsive/responsive_layout.dart';

/// The persistent application shell (§6/§7) every route in a `ShellRoute`
/// renders inside.
///
/// **Desktop** follows the reference designs: a floating header panel
/// carrying the brand, a pill bar of the primary destinations and the
/// account controls, with a slim icon rail down the side for the remaining
/// modules and the page content on the app canvas beside it.
///
/// The two surfaces are a *partition* of one module list, not two copies of
/// it (`splitNavItems`) — every enabled module is reachable from exactly
/// one of them, so §8's "no duplicate navigation menus" holds even though
/// the shell now has two navigation surfaces, as the references do.
///
/// **Tablet/mobile** keeps the drawer: a pill bar that scrolls and a rail
/// that eats 68px are both worse than a drawer on a phone.
///
/// One widget serves both the business app and the System Admin area — see
/// `routing/app_router.dart`.
///
/// The System Admin area passes a fixed [navItems]/[brandLabel]. The
/// business app passes neither and lets the shell resolve them live
/// ([AppShell.business]), which matters for more than tidiness: those two
/// values depend on the signed-in role's permissions (§24), the business
/// type (§33) and the authenticated business's name, and all three can
/// change mid-session — editing the permission matrix, for instance.
///
/// Resolving them *here* rather than inside `routerProvider`'s build is
/// what makes that safe. A provider watched while building the router makes
/// the router itself rebuild, which constructs a **brand-new `GoRouter`**
/// and throws away the navigation stack, dumping the user back at
/// `initialLocation`. The shell is an ordinary widget, so it just rebuilds.
class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.navItems,
    required this.brandLabel,
    required this.child,
    this.brandSubtitle,
    this.brandIcon,
    this.primaryRoutes = primaryNavRoutes,
    this.showSearch = true,
  });

  /// The business shell: nav items filtered by business type and the
  /// signed-in user's permissions, branded with the business's own name.
  const AppShell.business({super.key, required this.child})
      : navItems = null,
        brandLabel = null,
        brandSubtitle = null,
        brandIcon = null,
        primaryRoutes = primaryNavRoutes,
        showSearch = true;

  /// `null` means "resolve the business nav live" — see the class comment.
  final List<NavItem>? navItems;
  final String? brandLabel;

  /// Identity line under the brand — the System Admin area uses it to say
  /// so, which is how the two shells stay told apart (§3) while sharing
  /// one design system.
  final String? brandSubtitle;
  final IconData? brandIcon;

  /// Which destinations ride the header's pill bar; everything else goes
  /// to the rail. The System Admin area has few enough that they all fit
  /// up top, so it passes its own list.
  final List<String> primaryRoutes;

  final Widget child;

  /// The topbar's global search (business modules only — there's nothing
  /// for it to search in the System Admin area, which has its own
  /// per-screen search, e.g. `AdminBusinessesScreen`'s business-list
  /// search bar).
  final bool showSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.toString();
    final l10n = AppLocalizations.of(context)!;
    final navItems = this.navItems ?? enabledBusinessNavItems(ref);
    final brandLabel = this.brandLabel ?? businessBrandLabel(ref);
    var pageContext = brandLabel;
    for (final item in navItems) {
      if (currentPath == item.route || currentPath.startsWith('${item.route}/')) {
        pageContext = item.labelBuilder(l10n);
        break;
      }
    }

    return _MarkRouteSeen(
      route: currentPath,
      child: ResponsiveLayout(
        desktop: (context) => _DesktopShell(
        navItems: navItems,
        brandLabel: brandLabel,
        brandSubtitle: brandSubtitle,
        brandIcon: brandIcon,
        primaryRoutes: primaryRoutes,
        currentPath: currentPath,
        pageContext: pageContext,
        showSearch: showSearch,
        child: child,
      ),
      tablet: (context) => _CompactShell(
        navItems: navItems,
        brandLabel: brandLabel,
        brandSubtitle: brandSubtitle,
        brandIcon: brandIcon,
        currentPath: currentPath,
        pageContext: pageContext,
        showSearch: showSearch,
        child: child,
      ),
      mobile: (context) => _CompactShell(
        navItems: navItems,
        brandLabel: brandLabel,
        brandSubtitle: brandSubtitle,
        brandIcon: brandIcon,
        currentPath: currentPath,
        pageContext: pageContext,
          showSearch: showSearch,
          child: child,
        ),
      ),
    );
  }
}

/// Records that the destination now on screen has been looked at, so its
/// "arrived since you last opened it" badge clears.
///
/// A widget rather than a line in `AppShell.build`, for two reasons: writing to
/// storage during a build is a side effect in the wrong place, and this way the
/// mark happens once per route change instead of once per rebuild — the shell
/// rebuilds on every theme toggle, window resize and permission change.
///
/// It renders nothing of its own.
class _MarkRouteSeen extends ConsumerStatefulWidget {
  const _MarkRouteSeen({required this.route, required this.child});

  final String route;
  final Widget child;

  @override
  ConsumerState<_MarkRouteSeen> createState() => _MarkRouteSeenState();
}

class _MarkRouteSeenState extends ConsumerState<_MarkRouteSeen> {
  @override
  void initState() {
    super.initState();
    _mark();
  }

  @override
  void didUpdateWidget(_MarkRouteSeen old) {
    super.didUpdateWidget(old);
    if (old.route != widget.route) _mark();
  }

  /// After the frame, so the first paint of a screen is never waiting on a
  /// storage write, and errors here can never take a screen down with them —
  /// failing to remember a visit is worth a stale badge, not a blank page.
  void _mark() {
    final route = widget.route;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(navSeenMarkerProvider)(route).catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A floating chrome panel — the rounded white surface the header and the
/// rail sit on. One wrapper so the two can never drift apart on radius or
/// elevation.
class _ChromePanel extends StatelessWidget {
  const _ChromePanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: colors.border),
        boxShadow: AppElevation.cardShadow(colors, Theme.of(context).brightness),
      ),
      child: ClipRRect(borderRadius: AppRadius.cardRadius, child: child),
    );
  }
}

class _DesktopShell extends ConsumerWidget {
  const _DesktopShell({
    required this.navItems,
    required this.brandLabel,
    required this.brandSubtitle,
    required this.brandIcon,
    required this.primaryRoutes,
    required this.currentPath,
    required this.pageContext,
    required this.child,
    required this.showSearch,
  });

  final List<NavItem> navItems;
  final String brandLabel;
  final String? brandSubtitle;
  final IconData? brandIcon;
  final List<String> primaryRoutes;
  final String currentPath;
  final String pageContext;
  final Widget child;
  final bool showSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final split = splitNavItems(navItems, primaryRoutes: primaryRoutes);
    // An area small enough that every destination fits in the header gets
    // no rail at all — a 68px white column holding two controls reads as a
    // panel someone forgot to fill.
    final hasRailNav = split.secondary.isNotEmpty;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            _ChromePanel(
              child: AppTopBar(
                pageContext: pageContext,
                navItems: split.primary,
                currentPath: currentPath,
                brandLabel: brandLabel,
                brandSubtitle: brandSubtitle,
                brandIcon: brandIcon,
                showSearch: showSearch,
                showThemeToggle: !hasRailNav,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasRailNav) ...[
                  SizedBox(
                    width: AppRail.width,
                    child: _ChromePanel(
                      child: AppRail(
                        items: split.secondary,
                        currentPath: currentPath,
                        footer: [
                          RailActionButton(
                            icon: isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                            tooltip: isDark ? 'Light mode' : 'Dark mode',
                            onPressed: () => ref
                                .read(themeModeProvider.notifier)
                                .setMode(isDark ? ThemeMode.light : ThemeMode.dark),
                          ),
                          RailActionButton(
                            icon: Icons.logout,
                            tooltip: l10n.logout,
                            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  ],
                  Expanded(child: child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared by tablet and mobile — both use a `Drawer` holding the full
/// module list (no header/rail split down here: on a phone there is only
/// one navigation surface, so it carries everything). Stateful only so the
/// `GlobalKey` that opens the drawer is created once and stays stable
/// across rebuilds — a fresh key per `build()` would desync from the
/// `Scaffold` it's meant to address.
class _CompactShell extends StatefulWidget {
  const _CompactShell({
    required this.navItems,
    required this.brandLabel,
    required this.brandSubtitle,
    required this.brandIcon,
    required this.currentPath,
    required this.pageContext,
    required this.child,
    required this.showSearch,
  });

  final List<NavItem> navItems;
  final String brandLabel;
  final String? brandSubtitle;
  final IconData? brandIcon;
  final String currentPath;
  final String pageContext;
  final Widget child;
  final bool showSearch;

  @override
  State<_CompactShell> createState() => _CompactShellState();
}

class _CompactShellState extends State<_CompactShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Capped, not a flat 80% of the mobile breakpoint (480px) — on a
    // viewport narrower than that (e.g. a docked panel), that math let the
    // drawer swallow almost the entire screen with no way to see the page
    // behind it.
    final drawerWidth = MediaQuery.sizeOf(context).width * 0.8 < 288
        ? MediaQuery.sizeOf(context).width * 0.8
        : 288.0;

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        width: drawerWidth,
        child: AppSidebar(
          items: widget.navItems,
          currentPath: widget.currentPath,
          brandLabel: widget.brandLabel,
          brandSubtitle: widget.brandSubtitle,
          brandIcon: widget.brandIcon,
          // Reuses the same chevron control desktop used to collapse the
          // sidebar — here it closes the drawer instead, since a temporary
          // overlay has no "collapsed" state of its own, just open/closed.
          onCollapseToggle: () => _scaffoldKey.currentState?.closeDrawer(),
          // Picking a destination should also dismiss the overlay that
          // offered it; leaving it open hides the page just navigated to.
          onNavigate: () => _scaffoldKey.currentState?.closeDrawer(),
        ),
      ),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(72),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: AppTopBar(
            pageContext: widget.pageContext,
            // Navigation is also shown inline from the tablet breakpoint up,
            // not only behind the menu button.
            //
            // This shell covers everything from 600px to 1023px, which includes
            // a browser window beside an editor and a small laptop — and at
            // those sizes there is ample room for the pills, so hiding every
            // destination behind a hamburger made the app look like it had no
            // navigation at all. The menu stays, because it carries the full
            // list; these are the same pills the desktop shell shows, and
            // `_NavPills` already scrolls horizontally, so they cannot overflow
            // however many there are.
            //
            // Below 600px they are deliberately left out: the bar there is only
            // wide enough for the menu button, the page name and the account.
            navItems: context.isMobile ? const [] : widget.navItems,
            currentPath: widget.currentPath,
            onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
            showSearch: widget.showSearch,
          ),
        ),
      ),
      body: widget.child,
    );
  }
}
