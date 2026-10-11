import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'artifacts.dart';
import 'chat/app_panel.dart';
import 'chat/browser_panel.dart';
import 'chat/chat_view.dart';
import 'chat/cited_sources.dart';
import 'chat/gallery.dart';
import 'chat_sheet.dart';
import 'chat/passages_sheet.dart';
import 'files/files_view.dart';
import 'files/workspace_pages.dart';
import 'layout.dart';
import 'quick_switcher.dart';
import 'settings/settings_dialog.dart';
import 'share/share_sheet.dart';
import 'share/shared_item.dart';
import 'phone_drawer.dart';
import 'sidebar.dart';
import 'workspace_sheets.dart';
import 'sources/sources_panel.dart';
import 'activity.dart';
import 'upcoming.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'widgets/basics.dart';
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
  scope.shell.closePopup(Popup.workspaces);
  if (index < ordered.length && ordered[index].slug != scope.chat.activeSlug) {
    scope.chat.select(ordered[index].slug);
  }
}

/// The window: sidebar, chat and Sources, arranged for the width they have, with Settings over
/// them when it is open.
///
/// Below 820 the sidebar is a drawer from the left; below 1120 Sources is a drawer from the
/// right. On a phone the panel to the right, Sources, the browser or an app, is a sheet over
/// the chat instead. Esc and
/// Back close the topmost thing open: the popup, Settings, then a drawer, the app or the
/// browser.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) =>
      _ShareListener(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final t = Tokens.of(context);
    final duration = motion(context, const Duration(milliseconds: 250));

    /// What closes the thing on top, or null when nothing is open that Esc or Back closes:
    /// where Settings shows one page at a time, a page goes back first. The sidebar counts only
    /// while it is a drawer, and the panel to the right only while it is a drawer or a sheet,
    /// since one in the layout has nothing to close.
    VoidCallback? topClose({
      required bool settingsSideBySide,
      required bool sidebarDrawer,
      required bool phone,
      required bool rightClosable,
    }) {
      if (shell.shared != null) return shell.closeShared;
      if (shell.popup.value != null) return shell.closePopup;
      if (shell.scanning) return () => shell.setScanning(false);
      if (shell.phonePage != null && !shell.settingsOpen) {
        return shell.closePhonePage;
      }
      if (shell.settingsOpen) {
        return !settingsSideBySide && shell.settingsPage != null
            ? shell.settingsBack
            : shell.closeSettings;
      }
      if (sidebarDrawer && shell.sideOpen) return shell.closeSide;
      if (shell.appOpen) return shell.closeApp;
      if (shell.passagesOpen) return shell.closePassages;
      if (shell.citedOpen) return shell.closeCited;
      if (shell.browserOpen) return shell.closeBrowser;
      if (rightClosable && shell.rightOpen) return shell.closeSources;
      // A phone's workspace pages step back: a document's text, a page, then the chat.
      if (phone && shell.pane == Pane.files) {
        if (scope.files.reading != null) return scope.files.closeText;
        if (shell.workspacePage != null) {
          return () => shell.showWorkspacePage(null);
        }
        return () => shell.showPane(Pane.chats);
      }
      return null;
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
            // On a phone the panel to the right is a sheet over the chat, not a drawer.
            final sheet = screen.isPhone;
            final sourcesDrawer = !sourcesInline && !sheet && shell.rightOpen;
            final sheetOpen = sheet && shell.rightOpen;
            // A phone's drawer is wider, leaving the chat a strip to tap to close it.
            final drawerWidth = screen.isPhone
                ? max(Sizes.sidebar, min(360.0, box.maxWidth * 0.82))
                : Sizes.sidebar;
            // The panel to the right: Sources, or the chat's browser or an app, wider and never
            // wider than the screen.
            final rightWidth = switch (shell.beside) {
              Beside.sources ||
              Beside.passages ||
              Beside.cited => Sizes.sources,
              _ => min(Sizes.browser, box.maxWidth),
            };
            // Closed, the panel stays built for its closing animation; TickerMode, inside that
            // animation, tells a live card in it to let go.
            final right = TickerMode(
              enabled: shell.rightOpen,
              child: switch (shell.beside) {
                Beside.sources => const SourcesPanel(),
                Beside.browser => BrowserPanel(width: rightWidth),
                Beside.app => AppPanel(app: shell.app!, width: rightWidth),
                Beside.passages => const PassagesPanel(),
                Beside.cited => const CitedPanel(),
              },
            );
            VoidCallback? close() => topClose(
              settingsSideBySide: settingsSideBySide,
              sidebarDrawer: screen.sidebarDrawer,
              phone: screen.isPhone,
              rightClosable: sourcesDrawer || sheetOpen,
            );
            return _BackGuard(
              popup: shell.popup,
              open: close() != null,
              onBack: () => close()?.call(),
              child: CallbackShortcuts(
                bindings: {
                  // The browser takes these keys before a page sees them.
                  if (!kIsWeb) ...{
                    const SingleActivator(
                      LogicalKeyboardKey.keyK,
                      control: true,
                    ): shell.toggleSwitcher,
                    for (final (i, key) in _digits.indexed)
                      SingleActivator(key, control: true): () =>
                          _openWorkspace(scope, i),
                  },
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      close()?.call(),
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
                                        screen.isPhone
                                            ? const WorkspacePages()
                                            : FilesView(
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
                                width: drawerWidth,
                                duration: duration,
                                child: screen.isPhone
                                    ? PhoneDrawer(width: drawerWidth)
                                    : const Sidebar(),
                              ),
                            if (!sourcesInline && !sheet)
                              _Drawer(
                                open: sourcesDrawer,
                                left: false,
                                width: rightWidth,
                                duration: duration,
                                child: right,
                              ),
                            // The sheet's own scrim closes it.
                            if (sheetOpen) Positioned.fill(child: right),
                            // A phone puts back a deleted chat from over the chat, as its
                            // drawer has closed.
                            if (screen.isPhone && !shell.settingsOpen)
                              const _PhoneUndo(),
                            if (shell.phonePage case final page?)
                              Positioned.fill(
                                child: switch (page) {
                                  PhonePage.artifacts => const ArtifactsPage(),
                                  PhonePage.upcoming => const UpcomingPage(),
                                  PhonePage.activity => const ActivityPage(),
                                },
                              ),
                            // A phone's Settings is a page over the window.
                            if (shell.settingsOpen && screen.isPhone)
                              const Positioned.fill(
                                child: SettingsDialog(
                                  sideBySide: false,
                                  phone: true,
                                ),
                              )
                            else if (shell.settingsOpen) ...[
                              _Scrim(onTap: shell.closeSettings),
                              Center(
                                child: SettingsDialog(
                                  sideBySide: settingsSideBySide,
                                ),
                              ),
                            ],
                            // What another app shared, over everything but a popup.
                            if (shell.shared case final item?)
                              Positioned.fill(
                                child: ShareSheet(item, key: ObjectKey(item)),
                              ),
                            Positioned.fill(
                              child: ValueListenableBuilder(
                                valueListenable: shell.popup,
                                builder: (context, popup, _) => Stack(
                                  children: [
                                    if (popup case final GalleryOpen open)
                                      Positioned.fill(
                                        child: GalleryPage(
                                          open,
                                          key: ObjectKey(open),
                                        ),
                                      ),
                                    if (popup case final WorkspaceSheet kind)
                                      Positioned.fill(
                                        child: WorkspaceSheetView(
                                          kind,
                                          key: ValueKey(kind),
                                        ),
                                      ),
                                    if (popup case final CreatedSheetFor of)
                                      Positioned.fill(
                                        child: CreatedSheet(
                                          of,
                                          key: ValueKey((
                                            of.item.id,
                                            of.deleting,
                                          )),
                                        ),
                                      ),
                                    if (popup case final ChatSheetFor of)
                                      Positioned.fill(
                                        child: ChatSheet(
                                          of,
                                          key: ValueKey((
                                            of.thread.slug,
                                            of.deleting,
                                          )),
                                        ),
                                      ),
                                    if (popup == Popup.switcher) ...[
                                      _Scrim(
                                        onTap: () =>
                                            shell.closePopup(Popup.switcher),
                                      ),
                                      const Align(
                                        alignment: Alignment(0, -0.5),
                                        child: QuickSwitcher(),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
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

/// Undo for a chat just deleted, over a phone's chat, while it can be put back.
class _PhoneUndo extends StatelessWidget {
  const _PhoneUndo();

  @override
  Widget build(BuildContext context) {
    final chat = AppScope.of(context).chat;
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) => chat.deletedChat == null
          ? const SizedBox.shrink()
          : Positioned(
              left: 20,
              right: 20,
              bottom: 96,
              child: UndoBar(
                'Chat deleted',
                onUndo: chat.undoDelete,
                floating: true,
              ),
            ),
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

/// Back closes the topmost thing open, a [popup] or what [open] counts, through [onBack], and
/// leaves the app when nothing is. With the keyboard up it only puts the keyboard away, as
/// Android does elsewhere. It reads the keyboard and the popup itself, so the keyboard's
/// animation and a popup rebuild this and not [child].
class _BackGuard extends StatelessWidget {
  const _BackGuard({
    required this.popup,
    required this.open,
    required this.onBack,
    required this.child,
  });

  final ValueListenable<Object?> popup;
  final bool open;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    return ValueListenableBuilder(
      valueListenable: popup,
      builder: (context, popup, child) => PopScope(
        canPop: !typing && !open && popup == null,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (typing) {
            FocusManager.instance.primaryFocus?.unfocus();
          } else {
            onBack();
          }
        },
        child: child!,
      ),
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

/// Hands each item another app shares to the shell, which offers it in a sheet.
class _ShareListener extends StatefulWidget {
  const _ShareListener({required this.child});

  final Widget child;

  @override
  State<_ShareListener> createState() => _ShareListenerState();
}

class _ShareListenerState extends State<_ShareListener> {
  StreamSubscription<SharedItem>? _shares;

  @override
  void initState() {
    super.initState();
    final scope = AppScope.of(context);
    _shares = scope.shares?.listen(scope.shell.showShared);
  }

  @override
  void dispose() {
    _shares?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
