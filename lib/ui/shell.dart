import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'icons.dart';
import 'layout.dart';
import 'pages/router.dart';
import 'sidebar.dart';
import 'state/nav_controller.dart';
import 'tokens.dart';
import 'type.dart';
import 'widgets/brand.dart';
import 'widgets/buttons.dart';
import 'widgets/tappable.dart';

/// The window: sidebar and page, arranged for the width they have.
///
/// The shell and its media queries. See [ScreenClass] for the breakpoints.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppScope? _scope;
  AppRoute? _seen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    if (_scope != scope) {
      _scope?.nav.removeListener(_routeChanged);
      _scope = scope..nav.addListener(_routeChanged);
      _seen = scope.nav.route;
    }
  }

  @override
  void dispose() {
    _scope?.nav.removeListener(_routeChanged);
    super.dispose();
  }

  /// Showing a new page closes the drawer.
  void _routeChanged() {
    final scope = _scope!;
    if (scope.nav.route == _seen) return;
    _seen = scope.nav.route;
    scope.shell.close();
  }

  /// Back closes the drawer, then steps up from a document to its list. Only when neither applies
  /// does it leave the app.
  void _back() {
    final scope = _scope!;
    if (scope.shell.sideOpen) {
      scope.shell.close();
    } else if (scope.nav.parent case final parent?) {
      scope.nav.go(parent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final screen = ScreenClass.of(box.maxWidth);
        return ListenableBuilder(
          listenable: Listenable.merge([scope.nav, scope.shell]),
          builder: (context, child) => PopScope(
            canPop: !scope.shell.sideOpen && scope.nav.parent == null,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _back();
            },
            child: child!,
          ),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () {
                if (scope.shell.sideOpen) scope.shell.close();
              },
            },
            child: Focus(
              autofocus: true,
              // InkWell needs a Material above it, and the shell has no Scaffold.
              child: Material(
                color: t.bg,
                child: Column(
                  children: [
                    Expanded(child: _Frame(screen: screen)),
                    if (screen.hasTabBar) const _TabBar(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.screen});

  final ScreenClass screen;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final fast = MediaQuery.disableAnimationsOf(context);
    final duration = fast ? Duration.zero : const Duration(milliseconds: 250);
    return ListenableBuilder(
      listenable: scope.shell,
      builder: (context, _) {
        final shell = scope.shell;
        final sideDrawerOpen = screen.sidebarDrawer && shell.sideOpen;
        return Stack(
          children: [
            Row(
              children: [
                if (screen.sidebarInline) const Sidebar(),
                Expanded(
                  child: Column(
                    children: [
                      if (!screen.sidebarInline)
                        _TopBar(showMenu: screen.sidebarDrawer),
                      const Expanded(child: _MainArea()),
                    ],
                  ),
                ),
              ],
            ),
            if (sideDrawerOpen)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => shell.close(),
                  child: ColoredBox(color: t.scrim),
                ),
              ),
            if (screen.sidebarDrawer)
              _Drawer(
                open: sideDrawerOpen,
                duration: duration,
                child: const Sidebar(),
              ),
          ],
        );
      },
    );
  }
}

class _Drawer extends StatelessWidget {
  const _Drawer({
    required this.open,
    required this.duration,
    required this.child,
  });

  final bool open;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    bottom: 0,
    left: 0,
    width: Sizes.sidebar,
    child: ExcludeFocus(
      excluding: !open,
      child: ExcludeSemantics(
        excluding: !open,
        child: IgnorePointer(
          ignoring: !open,
          child: AnimatedSlide(
            duration: duration,
            curve: Curves.easeOut,
            offset: Offset(open ? 0 : -1.05, 0),
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// The current page, built afresh on each visit, which fetches its data again.
class _MainArea extends StatelessWidget {
  const _MainArea();

  @override
  Widget build(BuildContext context) {
    final nav = AppScope.of(context).nav;
    return ListenableBuilder(
      listenable: nav,
      builder: (context, _) =>
          KeyedSubtree(key: ValueKey(nav.route), child: pageFor(nav.route)),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.showMenu});

  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final shell = AppScope.of(context).shell;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        children: [
          if (showMenu) ...[
            IconBtn('menu', tooltip: 'Menu', onPressed: shell.toggle),
            const SizedBox(width: 10),
          ],
          const Brand(size: 22, logo: false),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: scope.nav,
      builder: (context, _) {
        final section = scope.nav.route.section;
        Widget tab(
          String icon,
          String label,
          bool current,
          VoidCallback onTap,
        ) {
          final color = current ? t.accent : t.muted;
          return Expanded(
            child: Tappable(
              label: label,
              selected: current,
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NilsIcon(icon, size: IconSize.big, color: color),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: Type.sans(
                        11,
                        weight: current ? FontWeight.w600 : FontWeight.w400,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Like Material's own navigation bar, keep the labels from outgrowing their tabs when the
        // person has asked for very large text.
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            decoration: BoxDecoration(
              color: t.side,
              border: Border(top: BorderSide(color: t.line)),
            ),
            child: Row(
              children: [
                for (final e in navEntries)
                  tab(
                    e.icon,
                    e.label,
                    section == e.route.section,
                    () => scope.nav.go(e.route),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
