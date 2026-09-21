import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../navigation/app_sidebar.dart';
import '../navigation/app_topbar.dart';
import '../navigation/nav_items.dart';
import '../navigation/sidebar_controller.dart';
import 'responsive/responsive_layout.dart';

/// The persistent application shell (§6) every route in a `ShellRoute`
/// renders inside — sidebar + top bar + content area, responsive per §5:
///  - Desktop: persistent, collapsible sidebar alongside the content.
///  - Tablet/mobile: sidebar becomes a `Drawer`, top bar gains a menu button.
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
    this.showSearch = true,
  });

  /// The business shell: nav items filtered by business type and the
  /// signed-in user's permissions, branded with the business's own name.
  const AppShell.business({super.key, required this.child})
      : navItems = null,
        brandLabel = null,
        showSearch = true;

  /// `null` means "resolve the business nav live" — see the class comment.
  final List<NavItem>? navItems;
  final String? brandLabel;
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

    return ResponsiveLayout(
      desktop: (context) => _DesktopShell(
        navItems: navItems,
        brandLabel: brandLabel,
        currentPath: currentPath,
        pageContext: pageContext,
        showSearch: showSearch,
        child: child,
      ),
      tablet: (context) => _CompactShell(
        navItems: navItems,
        brandLabel: brandLabel,
        currentPath: currentPath,
        pageContext: pageContext,
        showSearch: showSearch,
        child: child,
      ),
      mobile: (context) => _CompactShell(
        navItems: navItems,
        brandLabel: brandLabel,
        currentPath: currentPath,
        pageContext: pageContext,
        showSearch: showSearch,
        child: child,
      ),
    );
  }
}

class _DesktopShell extends ConsumerWidget {
  const _DesktopShell({
    required this.navItems,
    required this.brandLabel,
    required this.currentPath,
    required this.pageContext,
    required this.child,
    required this.showSearch,
  });

  final List<NavItem> navItems;
  final String brandLabel;
  final String currentPath;
  final String pageContext;
  final Widget child;
  final bool showSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(sidebarCollapsedProvider);
    final colors = context.colors;

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: collapsed ? 72 : 248,
            child: AppSidebar(
              items: navItems,
              currentPath: currentPath,
              brandLabel: brandLabel,
              collapsed: collapsed,
              onCollapseToggle: () => ref.read(sidebarCollapsedProvider.notifier).toggle(),
            ),
          ),
          VerticalDivider(width: 1, color: colors.border),
          Expanded(
            child: Column(
              children: [
                AppTopBar(pageContext: pageContext, showSearch: showSearch),
                Divider(height: 1, color: colors.border),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared by tablet and mobile — both use a `Drawer`, differing only in how
/// much of the top bar (e.g. inline search) fits (`AppTopBar` itself makes
/// that call based on width). Stateful only so the `GlobalKey` that opens
/// the drawer is created once and stays stable across rebuilds — a fresh
/// key per `build()` would desync from the `Scaffold` it's meant to address.
class _CompactShell extends StatefulWidget {
  const _CompactShell({
    required this.navItems,
    required this.brandLabel,
    required this.currentPath,
    required this.pageContext,
    required this.child,
    required this.showSearch,
  });

  final List<NavItem> navItems;
  final String brandLabel;
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
    // Capped, not a flat 80% of the mobile breakpoint (480px) — on a
    // viewport narrower than that (e.g. a docked panel), that math let the
    // drawer swallow almost the entire screen with no way to see the page
    // behind it.
    final drawerWidth = MediaQuery.sizeOf(context).width * 0.8 < 280
        ? MediaQuery.sizeOf(context).width * 0.8
        : 280.0;

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        width: drawerWidth,
        child: AppSidebar(
          items: widget.navItems,
          currentPath: widget.currentPath,
          brandLabel: widget.brandLabel,
          // Reuses the same chevron control desktop uses to collapse the
          // sidebar — here it closes the drawer instead, since a temporary
          // overlay has no "collapsed" state of its own, just open/closed.
          onCollapseToggle: () => _scaffoldKey.currentState?.closeDrawer(),
        ),
      ),
      appBar: AppTopBar(
        pageContext: widget.pageContext,
        onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
        showSearch: widget.showSearch,
      ),
      body: widget.child,
    );
  }
}
