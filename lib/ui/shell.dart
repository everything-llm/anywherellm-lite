import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'chat/chat_view.dart';
import 'chat/cited_sources.dart';
import 'chat/gallery.dart';
import 'chat_sheet.dart';
import 'chat/passages_sheet.dart';
import 'files/workspace_pages.dart';
import 'layout.dart';
import 'settings/settings_dialog.dart';
import 'share/share_sheet.dart';
import 'share/shared_item.dart';
import 'phone_drawer.dart';
import 'workspace_sheets.dart';
import 'sources/sources_panel.dart';
import 'upcoming.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'widgets/basics.dart';
import 'widgets/rise.dart';

/// The window: the chat, with the drawer from the left, the panel to the right as a sheet over
/// the chat, and Settings as a page over everything when it is open. Esc and Back close the
/// topmost thing open: the popup, a page over the chat, Settings, the drawer, the sheet, then
/// the workspace's pages.
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

    /// What closes the thing on top, or null when nothing is open that Esc or Back closes: in
    /// Settings, a page goes back to the list first.
    VoidCallback? topClose() {
      if (shell.shared != null) return shell.closeShared;
      if (shell.popup.value != null) return shell.closePopup;
      if (shell.scanning) return () => shell.setScanning(false);
      // What the sheet over the chat shows, which sits over a page too.
      VoidCallback? side() {
        if (shell.passagesOpen) return shell.closePassages;
        if (shell.citedOpen) return shell.closeCited;
        if (shell.rightOpen) return shell.closeSources;
        return null;
      }

      if (shell.phonePage != null && !shell.settingsOpen) {
        return side() ?? shell.closePhonePage;
      }
      if (shell.settingsOpen) {
        return shell.settingsPage != null
            ? shell.settingsBack
            : shell.closeSettings;
      }
      if (shell.sideOpen) return shell.closeSide;
      if (side() case final close?) return close;
      // The workspace's pages step back: a document's text, a page, then the chat.
      if (shell.pane == Pane.files) {
        if (scope.files.reading != null) return scope.files.closeText;
        if (shell.workspacePage != null) {
          return () => shell.showWorkspacePage(null);
        }
        return () => shell.showPane(Pane.chats);
      }
      return null;
    }

    return LayoutBuilder(
      builder: (context, box) => ListenableBuilder(
        listenable: shell,
        builder: (context, _) {
          final files = shell.pane == Pane.files;
          // The drawer leaves the chat a strip to tap to close it.
          final drawerWidth = max(
            Sizes.drawer,
            min(360.0, box.maxWidth * 0.82),
          );
          final right = switch (shell.beside) {
            Beside.sources => const SourcesPanel(),
            Beside.passages => const PassagesPanel(),
            Beside.cited => const CitedPanel(),
          };
          return _BackGuard(
            popup: shell.popup,
            open: topClose() != null,
            onBack: () => topClose()?.call(),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    topClose()?.call(),
              },
              child: Focus(
                autofocus: true,
                // InkWell needs a Material above it, and the shell has no Scaffold.
                child: Material(
                  color: t.bg,
                  child: _AboveKeyboard(
                    // Clear of the status and navigation bars.
                    child: SafeArea(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // The chat stays built while the workspace's pages show, so a
                                // draft and a running answer survive the switch.
                                Offstage(
                                  offstage: files,
                                  child: TickerMode(
                                    enabled: !files,
                                    child: ExcludeFocus(
                                      excluding: files,
                                      child: const ChatView(),
                                    ),
                                  ),
                                ),
                                if (files) const WorkspacePages(),
                              ],
                            ),
                          ),
                          if (shell.sideOpen) _Scrim(onTap: shell.closeSide),
                          _Drawer(
                            open: shell.sideOpen,
                            width: drawerWidth,
                            duration: duration,
                            child: PhoneDrawer(width: drawerWidth),
                          ),
                          if (shell.phonePage case final page?)
                            Positioned.fill(
                              child: switch (page) {
                                PhonePage.upcoming => const UpcomingPage(),
                              },
                            ),
                          // The sheet's own scrim closes it. It sits over a page, as the
                          // drawer that opens a page cannot be reached under it.
                          if (shell.rightOpen) Positioned.fill(child: right),
                          // A deleted chat is put back from over the chat, as the drawer has
                          // closed.
                          if (!shell.settingsOpen) const _PhoneUndo(),
                          if (shell.settingsOpen)
                            const Positioned.fill(child: SettingsDialog()),
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
      ),
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
    required this.width,
    required this.duration,
    required this.child,
  });

  final bool open;
  final double width;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(
    top: 0,
    bottom: 0,
    left: 0,
    width: width,
    child: _Hidden(
      hidden: !open,
      child: AnimatedSlide(
        duration: duration,
        curve: Curves.easeOut,
        offset: Offset(open ? 0 : -1.05, 0),
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
