import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_colors.dart';
import '../navigation/app_sidebar.dart';
import '../navigation/app_topbar.dart';
import '../navigation/nav_items.dart';
import '../navigation/sidebar_controller.dart';
import 'responsive/app_breakpoints.dart';
import 'responsive/responsive_layout.dart';

/// The persistent application shell (§6) every route in a `ShellRoute`
/// renders inside — sidebar + top bar + content area, responsive per §5:
///  - Desktop: persistent, collapsible sidebar alongside the content.
///  - Tablet/mobile: sidebar becomes a `Drawer`, top bar gains a menu button.
///
/// One widget serves both the business app and the System Admin area
/// (`AppRouter` passes different `navItems`/`brandLabel`) — see
/// `routing/app_router.dart`.
class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.navItems,
    required this.brandLabel,
    required this.child,
  });

  final List<NavItem> navItems;
  final String brandLabel;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = GoRouterState.of(context).uri.toString();
    final l10n = AppLocalizations.of(context)!;
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
        child: child,
      ),
      tablet: (context) => _CompactShell(
        navItems: navItems,
        brandLabel: brandLabel,
        currentPath: currentPath,
        pageContext: pageContext,
        child: child,
      ),
      mobile: (context) => _CompactShell(
        navItems: navItems,
        brandLabel: brandLabel,
        currentPath: currentPath,
        pageContext: pageContext,
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
  });

  final List<NavItem> navItems;
  final String brandLabel;
  final String currentPath;
  final String pageContext;
  final Widget child;

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
                AppTopBar(pageContext: pageContext),
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
  });

  final List<NavItem> navItems;
  final String brandLabel;
  final String currentPath;
  final String pageContext;
  final Widget child;

  @override
  State<_CompactShell> createState() => _CompactShellState();
}

class _CompactShellState extends State<_CompactShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        width: AppBreakpoints.mobile * 0.8,
        child: AppSidebar(
          items: widget.navItems,
          currentPath: widget.currentPath,
          brandLabel: widget.brandLabel,
        ),
      ),
      appBar: AppTopBar(
        pageContext: widget.pageContext,
        onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      body: widget.child,
    );
  }
}
