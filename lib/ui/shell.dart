import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'chat/browser_sheet.dart';
import 'chat/chat_view.dart';
import 'chat/cited_sources.dart';
import 'chat/gallery.dart';
import 'chat_sheet.dart';
import 'chat/page_sheet.dart';
import 'chat/passages_sheet.dart';
import 'files/workspace_pages.dart';
import 'settings/pairing_sheet.dart';
import 'settings/settings_dialog.dart';
import 'share/share_sheet.dart';
import 'shelf.dart';
import 'share/shared_item.dart';
import 'workspace_sheets.dart';
import 'sources/sources_panel.dart';
import 'activity.dart';
import 'library.dart';
import 'upcoming.dart';
import 'workspace_switcher.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'widgets/keyboard_up.dart';
import 'widgets/basics.dart';
import 'widgets/sheet.dart';
import 'widgets/window_insets.dart';

/// The window: the chat, which is the base screen; the chats as a shelf over it, with Settings
/// at its foot; the workspace's pages or Upcoming over those; Settings, its list or a page, over
/// them all; and the sheets and popups over the whole window. Esc and Back close the topmost
/// thing open: the popup, Settings' page, the shelf, the sheet, Upcoming, the workspace's pages a
/// step at a time; with nothing open Back puts the app out of sight.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) =>
      _ShareListener(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final t = Tokens.of(context);

    /// What closes the thing on top, or null when nothing is open that Esc or Back closes: in
    /// Settings, a page goes back to its parent first.
    VoidCallback? topClose() {
      // The guide and the camera lie over the whole window, a share and the popups too.
      if (shell.guiding) return () => shell.showGuide(null);
      if (shell.scanning) return () => shell.setScanning(false);
      if (shell.shared != null) return shell.closeShared;
      if (shell.popup.value != null) return shell.closePopup;
      if (shell.settingsOpen) return shell.settingsBack;
      if (shell.shelfOpen) return shell.closeShelf;
      if (shell.passagesOpen) return shell.closePassages;
      if (shell.citedOpen) return shell.closeCited;
      if (shell.rightOpen) return shell.closeSources;
      if (shell.toolkitPage != null) return shell.closeToolkitPage;
      // The workspace's pages step back: a document's text, a page, then what they opened over.
      if (shell.pane == Pane.files) {
        if (scope.files.reading != null) return () => closeDocText(scope);
        if (shell.workspacePage != null) {
          return () => shell.showWorkspacePage(null);
        }
        return () => shell.showPane(Pane.chats);
      }
      return null;
    }

    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) {
        final files = shell.pane == Pane.files;
        // The chat is the base screen: it shows unless the workspace's pages, a page of the
        // toolkit's or Settings cover it.
        final chatShown =
            !files && shell.toolkitPage == null && !shell.settingsOpen;
        final right = switch (shell.beside) {
          Beside.sources => const SourcesPanel(),
          Beside.passages => const PassagesPanel(),
          Beside.cited => const CitedPanel(),
        };
        // WindowInsets holds the bars' insets from before any page is padded by them, for what
        // reaches the window's edges: the scrims, the sheets and the shelf.
        return WindowInsets(
          child: _BackGuard(
            popup: shell.popup,
            open: topClose() != null,
            onBack: () => topClose()?.call(),
            onLeave: switch (scope.background) {
              final background? => () => unawaited(background.leave()),
              null => null,
            },
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
                    // Full window: each page keeps itself clear of the system bars, and what
                    // reaches the window's edges, the scrims, sheets and shelf, covers them.
                    child: Stack(
                      children: [
                        // The chat stays built while it is off the screen, so a draft and a
                        // running answer survive.
                        Positioned.fill(
                          child: Offstage(
                            offstage: !chatShown,
                            child: TickerMode(
                              enabled: chatShown,
                              child: ExcludeFocus(
                                excluding: !chatShown,
                                child: ColoredBox(
                                  color: t.bg,
                                  child: const SafeArea(child: ChatView()),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // The chats as a shelf from the left over the chat.
                        if (shell.shelfOpen)
                          const Positioned.fill(child: ChatsShelf()),
                        if (files)
                          Positioned.fill(
                            child: ColoredBox(
                              color: t.bg,
                              child: const SafeArea(
                                bottom: false,
                                child: WorkspacePages(),
                              ),
                            ),
                          ),
                        if (shell.toolkitPage case final page?)
                          Positioned.fill(
                            child: SafeArea(
                              bottom: false,
                              child: switch (page) {
                                ToolkitPage.upcoming => const UpcomingPage(),
                                ToolkitPage.library => const LibraryPage(),
                                ToolkitPage.activity => const ActivityPage(),
                              },
                            ),
                          ),
                        // A deleted chat is put back from over the chat's composer.
                        if (!shell.settingsOpen) const _PhoneUndo(),
                        // The sheet's own scrim closes it.
                        if (shell.rightOpen) Positioned.fill(child: right),
                        // Over the sheet, since a page opened from elsewhere, as a pairing
                        // link opens Connection, shows over what showed.
                        if (shell.settingsOpen)
                          const Positioned.fill(
                            child: SafeArea(
                              bottom: false,
                              child: SettingsDialog(),
                            ),
                          ),
                        // What another app shared, over everything but a popup.
                        if (shell.shared case final SharedPairing link)
                          Positioned.fill(
                            child: PairingSheet(
                              link.code,
                              key: ObjectKey(link),
                            ),
                          )
                        else if (shell.shared case final SharedContent item)
                          Positioned.fill(
                            child: ShareSheet(item, key: ObjectKey(item)),
                          ),
                        Positioned.fill(
                          child: ValueListenableBuilder(
                            valueListenable: shell.popup,
                            builder: (context, popup, _) => Stack(
                              children: [
                                if (popup == Popup.workspaces)
                                  Positioned.fill(
                                    child: ModalSheet(
                                      title: 'Workspaces',
                                      onClose: () =>
                                          shell.closePopup(Popup.workspaces),
                                      child: SingleChildScrollView(
                                        child: WorkspaceMenu(
                                          onCreate: () => shell.togglePopup(
                                            WorkspaceSheet.create,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
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
                                if (popup case BrowserOpen(:final tab))
                                  Positioned.fill(
                                    child: BrowserSheet(
                                      tab,
                                      key: ValueKey(tab),
                                    ),
                                  ),
                                if (popup case PageOpen(:final page))
                                  Positioned.fill(
                                    child: PageSheet(page, key: ValueKey(page)),
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
    );
  }
}

/// Undo for a chat just deleted, over the chat's composer while it can be put back.
class _PhoneUndo extends StatelessWidget {
  const _PhoneUndo();

  @override
  Widget build(BuildContext context) {
    final chat = AppScope.of(context).chat;
    final bars = WindowInsets.of(context);
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) => chat.deletedChat == null
          ? const SizedBox.shrink()
          : Positioned(
              left: 20 + bars.left,
              right: 20 + bars.right,
              bottom: 96 + bars.bottom,
              child: UndoBar(
                'Chat deleted',
                onUndo: chat.undoDelete,
                floating: true,
              ),
            ),
    );
  }
}

/// Back closes the topmost thing open, a [popup] or what [open] counts, through [onBack], and
/// leaves the app when nothing is, through [onLeave] where there is one. With the keyboard up it only puts the keyboard away, as
/// Android does elsewhere. It reads the keyboard and the popup itself, so the keyboard's
/// animation and a popup rebuild this and not [child].
class _BackGuard extends StatelessWidget {
  const _BackGuard({
    required this.popup,
    required this.open,
    required this.onBack,
    required this.onLeave,
    required this.child,
  });

  final ValueListenable<Object?> popup;
  final bool open;
  final VoidCallback onBack;

  /// Puts the app out of sight when nothing is open, in place of closing it, so an answer it
  /// holds goes on; null lets Back close the app.
  final VoidCallback? onLeave;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
    return ValueListenableBuilder(
      valueListenable: popup,
      builder: (context, popup, child) => PopScope(
        canPop: !typing && !open && popup == null && onLeave == null,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (typing) {
            FocusManager.instance.primaryFocus?.unfocus();
          } else if (open || popup != null) {
            onBack();
          } else {
            onLeave?.call();
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
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: KeyboardUp(
        up: inset > 0,
        child: MediaQuery.removeViewInsets(
          context: context,
          removeBottom: true,
          child: child,
        ),
      ),
    );
  }
}

/// Hands each item another app shares to the shell, which offers it in a sheet. A signed-in link
/// shows no sheet: the chat comes back with the message in its composer, sent only by the person.
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
    _shares = scope.shares?.listen(_take);
  }

  void _take(SharedItem item) {
    final scope = AppScope.of(context);
    if (item is SharedSignIn) {
      scope.shell.openChat();
      scope.chat.putInComposer(item.message, const []);
    } else {
      scope.shell.showShared(item);
    }
  }

  @override
  void dispose() {
    _shares?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
