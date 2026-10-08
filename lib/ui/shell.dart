import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'chat/browser_panel.dart';
import 'chat/chat_view.dart';
import 'files/files_view.dart';
import 'layout.dart';
import 'settings/settings_dialog.dart';
import 'sidebar.dart';
import 'sources/sources_panel.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'widgets/rise.dart';

/// Ctrl and these open the workspaces in the sidebar's order.
const _digits = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// Opens the [index]th workspace in the order the sidebar's menu lists them.
void _openWorkspace(AppScope scope, int index) {
  final ordered = scope.prefs.prefs.inOrder(
    scope.chat.workspaces,
    (w) => w.slug,
  );
  scope.shell.closeMenu();
  if (index < ordered.length && ordered[index].slug != scope.chat.activeSlug) {
    scope.chat.select(ordered[index].slug);
  }
}

/// Moves to the sidebar's search, showing the chats and opening the sidebar where it is a
/// [drawer].
void _findChats(AppScope scope, {required bool drawer}) {
  final shell = scope.shell..showPane(Pane.chats);
  if (drawer && !shell.sideOpen) shell.toggleSide();
  // The field is built in this frame when the drawer has just opened.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => shell.searchFocus.requestFocus(),
  );
}

/// The window: sidebar, chat and Sources, arranged for the width they have, with Settings over
/// them when it is open.
///
/// Below 820 the sidebar is a drawer from the left; below 1120 Sources is a drawer from the
/// right. Esc and Back close the topmost thing open: the workspace menu, Settings, then a
/// drawer.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final t = Tokens.of(context);
    final duration = motion(context, const Duration(milliseconds: 250));

    /// Closes what is on top; where Settings shows one page at a time, a page goes back to the
    /// list first. The sidebar counts only while it is a drawer, since an inline one has nothing
    /// to close.
    bool closeTop({
      required bool settingsSideBySide,
      required bool sidebarDrawer,
    }) {
      if (shell.menuOpen) {
        shell.closeMenu();
      } else if (shell.settingsOpen &&
          !settingsSideBySide &&
          shell.settingsPage != null) {
        shell.showSettingsPage(null);
      } else if (shell.settingsOpen) {
        shell.closeSettings();
      } else if (sidebarDrawer && shell.sideOpen) {
        shell.closeSide();
      } else if (shell.browserOpen) {
        shell.closeBrowser();
      } else {
        return false;
      }
      return true;
    }

    return LayoutBuilder(
      builder: (context, box) {
        final screen = ScreenClass.of(box.maxWidth);
        final sourcesInline = ScreenClass.sourcesInline(box.maxWidth);
        final settingsSideBySide = ScreenClass.settingsSideBySide(box.maxWidth);
        shell.fit(sourcesInline: sourcesInline);
        return ListenableBuilder(
          listenable: shell,
          builder: (context, _) {
            final sideDrawer = screen.sidebarDrawer && shell.sideOpen;
            final files = shell.pane == Pane.files;
            final sourcesDrawer = !sourcesInline && shell.rightOpen;
            final browser = shell.rightShowsBrowser;
            // The panel to the right: Sources, or the chat's browser, wider and never wider
            // than the screen.
            final rightWidth = browser
                ? min(Sizes.browser, box.maxWidth)
                : Sizes.sources;
            // Closed, the panel stays built for its closing animation; TickerMode, inside that
            // animation, tells a live card in it to let go.
            final right = TickerMode(
              enabled: shell.rightOpen,
              child: browser
                  ? BrowserPanel(width: rightWidth)
                  : const SourcesPanel(),
            );
            return _BackGuard(
              open:
                  shell.settingsOpen ||
                  shell.menuOpen ||
                  sideDrawer ||
                  sourcesDrawer ||
                  shell.browserOpen,
              onBack: () {
                if (!closeTop(
                  settingsSideBySide: settingsSideBySide,
                  sidebarDrawer: screen.sidebarDrawer,
                )) {
                  shell.closeSources();
                }
              },
              child: CallbackShortcuts(
                bindings: {
                  // The browser takes these keys before a page sees them.
                  if (!kIsWeb) ...{
                    const SingleActivator(
                      LogicalKeyboardKey.keyK,
                      control: true,
                    ): () =>
                        _findChats(scope, drawer: screen.sidebarDrawer),
                    for (final (i, key) in _digits.indexed)
                      SingleActivator(key, control: true): () =>
                          _openWorkspace(scope, i),
                  },
                  const SingleActivator(LogicalKeyboardKey.escape): () {
                    if (!closeTop(
                          settingsSideBySide: settingsSideBySide,
                          sidebarDrawer: screen.sidebarDrawer,
                        ) &&
                        sourcesDrawer) {
                      shell.closeSources();
                    }
                  },
                },
                child: Focus(
                  autofocus: true,
                  // InkWell needs a Material above it, and the shell has no Scaffold.
                  child: Material(
                    color: t.bg,
                    child: _AboveKeyboard(
                      // Clear of the status and navigation bars on a phone; no inset on a
                      // desktop.
                      child: SafeArea(
                        child: Stack(
                          children: [
                            Row(
                              children: [
                                if (screen.sidebarInline) const Sidebar(),
                                // Keyed, so the chat keeps its state when the panels on both
                                // sides come or go in one resize.
                                Expanded(
                                  key: const ValueKey('main'),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      // The chat stays built while Files is on screen, so a draft
                                      // and a running answer survive the switch.
                                      Offstage(
                                        offstage: files,
                                        child: TickerMode(
                                          enabled: !files,
                                          child: ExcludeFocus(
                                            excluding: files,
                                            child: ChatView(
                                              showMenu: screen.sidebarDrawer,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (files)
                                        FilesView(
                                          showMenu: screen.sidebarDrawer,
                                        ),
                                    ],
                                  ),
                                ),
                                if (sourcesInline)
                                  AnimatedContainer(
                                    duration: duration,
                                    curve: Curves.easeOut,
                                    width: shell.rightOpen ? rightWidth : 0,
                                    child: ClipRect(
                                      child: OverflowBox(
                                        alignment: Alignment.centerLeft,
                                        minWidth: rightWidth,
                                        maxWidth: rightWidth,
                                        child: _Hidden(
                                          hidden: !shell.rightOpen,
                                          child: right,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (sideDrawer || sourcesDrawer)
                              _Scrim(onTap: shell.closeDrawers),
                            if (screen.sidebarDrawer)
                              _Drawer(
                                open: sideDrawer,
                                left: true,
                                width: Sizes.sidebar,
                                duration: duration,
                                child: const Sidebar(),
                              ),
                            if (!sourcesInline)
                              _Drawer(
                                open: sourcesDrawer,
                                left: false,
                                width: rightWidth,
                                duration: duration,
                                child: right,
                              ),
                            if (shell.settingsOpen) ...[
                              _Scrim(onTap: shell.closeSettings),
                              Center(
                                child: SettingsDialog(
                                  sideBySide: settingsSideBySide,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ColoredBox(color: Tokens.of(context).scrim),
    ),
  );
}

/// Takes [child] out of focus, semantics and hit testing while it is out of sight.
class _Hidden extends StatelessWidget {
  const _Hidden({required this.hidden, required this.child});

  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    excluding: hidden,
    child: ExcludeSemantics(
      excluding: hidden,
      child: IgnorePointer(ignoring: hidden, child: child),
    ),
  );
}

class _Drawer extends StatelessWidget {
  const _Drawer({
    required this.open,
    required this.left,
    required this.width,
    required this.duration,
    required this.child,
  });

  final bool open;

  /// Slides from the left edge, or else from the right.
  final bool left;
  final double width;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    bottom: 0,
    left: left ? 0 : null,
    right: left ? null : 0,
    width: width,
    child: _Hidden(
      hidden: !open,
      child: AnimatedSlide(
        duration: duration,
        curve: Curves.easeOut,
        offset: Offset(open ? 0 : (left ? -1.05 : 1.05), 0),
        child: child,
      ),
    ),
  );
}

/// Back closes the topmost thing [open] through [onBack], and leaves the app when nothing is.
/// With the keyboard up it only puts the keyboard away, as Android does elsewhere. It reads the
/// keyboard itself, so the keyboard's animation rebuilds this and not [child].
class _BackGuard extends StatelessWidget {
  const _BackGuard({
    required this.open,
    required this.onBack,
    required this.child,
  });

  final bool open;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      canPop: !typing && !open,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (typing) {
          FocusManager.instance.primaryFocus?.unfocus();
        } else {
          onBack();
        }
      },
      child: child,
    );
  }
}

/// [child] above the on-screen keyboard. Android keeps the window full height under the
/// keyboard and reports it as a bottom view inset, which a Scaffold would stand clear of; the
/// shell has none. The inset is taken out below, so nothing applies it twice, and the
/// keyboard's animation rebuilds this and not [child].
class _AboveKeyboard extends StatelessWidget {
  const _AboveKeyboard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: child,
    ),
  );
}
