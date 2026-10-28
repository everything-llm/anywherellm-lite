import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/copy.dart';
import 'app_scope.dart';
import 'chat/chat_view.dart';
import 'chat/cited_sources.dart';
import 'chat/gallery.dart';
import 'chat_sheet.dart';
import 'chat/passages_sheet.dart';
import 'files/documents_pane.dart';
import 'files/workspace_pages.dart';
import 'settings/pairing_sheet.dart';
import 'settings/settings_dialog.dart';
import 'share/share_sheet.dart';
import 'layout.dart';
import 'shelf.dart';
import 'sidebar.dart';
import 'share/shared_item.dart';
import 'workspace_sheets.dart';
import 'sources/sources_panel.dart';
import 'workspace_switcher.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'widgets/keyboard_up.dart';
import 'widgets/basics.dart';
import 'widgets/sheet.dart';
import 'widgets/window_insets.dart';

/// The window: the chat, which is the base screen; the chats as a shelf over it, with Settings
/// at its foot; the workspace's pages over those; Settings, its list or a page, over them all;
/// and the sheets and popups over the whole window. Esc and Back close the topmost thing open: a
/// walk-through, the camera, what another app shared, the popup, Settings' page, the shelf, the
/// sheet, the workspace's pages a step at a time; with nothing open Back
/// puts the app out of sight.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) => WideScope(
    child: _ShareListener(child: Builder(builder: _build)),
  );

  Widget _build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final t = Tokens.of(context);
    // From wide enough, the chats are a sidebar beside everything, in place of the shelf.
    final sidebar = Wide.sidebarShown(context);
    final split = Wide.split(context);
    // The sidebar takes the shelf's place, so a shelf left open does not come back narrower.
    if (sidebar && shell.shelfOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => shell.closeShelf());
    }

    /// What closes the thing on top, or null when nothing is open that Esc or Back closes: in
    /// Settings, a page goes back to its parent first.
    VoidCallback? topClose() {
      // The guide and the camera lie over the whole window, a share and the popups too.
      if (shell.guiding) return () => shell.showGuide(null);
      if (shell.scanning) return () => shell.setScanning(false);
      if (shell.shared != null) return shell.closeShared;
      if (shell.popup.value != null) return shell.closePopup;
      if (shell.settingsOpen) return () => shell.settingsBack(split: split);
      if (shell.shelfOpen && !sidebar) return shell.closeShelf;
      if (shell.passagesOpen) return shell.closePassages;
      if (shell.citedOpen) return shell.closeCited;
      if (shell.rightOpen) return shell.closeSources;
      // The workspace's pages step back: a document's text, a page, then what they opened over.
      if (shell.pane == Pane.files) {
        if (scope.files.reading != null) return () => closeDocText(scope);
        if (shell.workspacePage != null) {
          return () => shell.showWorkspacePage(null);
        }
        return () => shell.showPane(Pane.chats);
      }
      if (shell.pane != Pane.chats) return shell.closePane;
      return null;
    }

    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) {
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
                  color: t.ground,
                  child: _AboveKeyboard(
                    // Full window: each page keeps itself clear of the system bars, and what
                    // reaches the window's edges, the scrims, sheets and shelf, covers them.
                    child: Stack(
                      children: [
                        Positioned.fill(child: _Main(sidebar: sidebar)),
                        // The sheet's own scrim closes it.
                        if (shell.rightOpen) Positioned.fill(child: right),
                        // Over the sheet, since a page opened from elsewhere, as a pairing
                        // link opens Connection, shows over what showed.
                        if (shell.settingsOpen && !sidebar)
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
                            // The popups drawn over the whole window; the rest draw where
                            // they open.
                            builder: (context, popup, _) => switch (popup) {
                              Popup.workspaces => ModalSheet(
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
                              final GalleryOpen open => GalleryPage(
                                open,
                                key: ObjectKey(open),
                              ),
                              final WorkspaceSheet kind => WorkspaceSheetView(
                                kind,
                                key: ValueKey(kind),
                              ),
                              final ChatSheetFor of => ChatSheet(
                                of,
                                key: ValueKey(of.thread.slug),
                              ),
                              _ => const SizedBox.shrink(),
                            },
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

/// What the window shows under the sheets and popups: the chat, the shelf, the pane over the chat
/// and, beside the [sidebar] when it shows, Settings.
class _Main extends StatelessWidget {
  const _Main({required this.sidebar});

  final bool sidebar;

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    final t = Tokens.of(context);
    // The chat is the base screen: it shows unless another pane or Settings cover it.
    final chatShown = shell.pane == Pane.chats && !shell.settingsOpen;
    final pane = switch (shell.pane) {
      Pane.chats => null,
      Pane.files => const WorkspacePages(),
      Pane.documents => const DocumentsPane(),
    };
    final region = Stack(
      children: [
        // The chat stays built while it is off the screen, so a draft and a running answer
        // survive.
        Positioned.fill(
          child: Offstage(
            offstage: !chatShown,
            child: TickerMode(
              enabled: chatShown,
              child: ExcludeFocus(
                excluding: !chatShown,
                child: ColoredBox(
                  color: t.ground,
                  child: const SafeArea(child: ChatView()),
                ),
              ),
            ),
          ),
        ),
        // The chats as a shelf from the left over the chat.
        if (shell.shelfOpen && !sidebar)
          const Positioned.fill(child: ChatsShelf()),
        if (pane != null)
          Positioned.fill(
            child: ColoredBox(
              color: t.ground,
              child: SafeArea(bottom: false, child: pane),
            ),
          ),
        // A deleted chat is put back from over the chat's composer.
        if (!shell.settingsOpen) const _PhoneUndo(),
        // Beside the sidebar, Settings takes the room the chat has.
        if (shell.settingsOpen && sidebar)
          const Positioned.fill(
            child: SafeArea(bottom: false, child: SettingsDialog()),
          ),
      ],
    );
    // The region keeps its place in the row whether the sidebar shows or not, so the chat
    // survives the window crossing the sidebar's width.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sidebar) const SizedBox(width: Wide.sidebar, child: Sidebar()),
        Expanded(
          // The sidebar keeps clear of the window's left edge.
          child: MediaQuery.removePadding(
            context: context,
            removeLeft: sidebar,
            child: region,
          ),
        ),
      ],
    );
  }
}

/// Undo for a chat just deleted, or for the waiting messages Clear all took out, over the chat's
/// composer while they can be put back, with Close, which lets them go.
class _PhoneUndo extends StatelessWidget {
  const _PhoneUndo();

  @override
  Widget build(BuildContext context) {
    final chat = AppScope.of(context).chat;
    final bars = WindowInsets.of(context);
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final (String, VoidCallback, VoidCallback)? undo =
            chat.deletedChat != null
            ? (
                'Chat deleted',
                chat.undoDelete,
                () => unawaited(chat.flushDelete()),
              )
            : switch (chat.clearedOnDeck) {
                final n? => (
                  'Cleared ${plural(n, 'waiting message', 'waiting messages')}',
                  chat.undoClearOnDeck,
                  chat.closeClearedOnDeck,
                ),
                null => null,
              };
        if (undo == null) return const SizedBox.shrink();
        return Positioned(
          left: 20 + bars.left,
          right: 20 + bars.right,
          bottom: 96 + bars.bottom,
          child: UndoBar(
            undo.$1,
            onUndo: undo.$2,
            onClose: undo.$3,
            floating: true,
          ),
        );
      },
    );
  }
}

/// Back closes the topmost thing open, a [popup] or what [open] counts, through [onBack], and
/// leaves the app when nothing is, through [onLeave] where there is one. With the keyboard up it
/// only puts the keyboard away, as Android does elsewhere. It reads the keyboard and the popup
/// itself, so the keyboard's animation and a popup rebuild this and not [child].
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
    return ListenableBuilder(
      listenable: popup,
      builder: (context, child) {
        final above = popup.value != null;
        return PopScope(
          canPop: !typing && !open && !above && onLeave == null,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (typing) {
              FocusManager.instance.primaryFocus?.unfocus();
            } else if (open || above) {
              onBack();
            } else {
              onLeave?.call();
            }
          },
          child: child!,
        );
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
