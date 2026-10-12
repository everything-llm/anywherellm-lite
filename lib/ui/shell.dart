import 'dart:async';

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
import 'settings/settings_dialog.dart';
import 'share/share_sheet.dart';
import 'share/shared_item.dart';
import 'home.dart';
import 'workspace_sheets.dart';
import 'sources/sources_panel.dart';
import 'upcoming.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'widgets/basics.dart';

/// The window: the home, the Chats tab or Settings' list over the bar of tabs; the chat full
/// screen over it; the workspace's pages or Upcoming over those; the sheet over the chat; and
/// a page of Settings over everything when one is open. Esc and Back close the topmost thing
/// open: the popup, Settings' page, the sheet, Upcoming, the workspace's pages a step at a
/// time, then the chat.
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
      if (shell.shared != null) return shell.closeShared;
      if (shell.popup.value != null) return shell.closePopup;
      if (shell.scanning) return () => shell.setScanning(false);
      if (shell.settingsOpen) {
        return shell.settingsPage != null
            ? shell.settingsBack
            : shell.closeSettings;
      }
      if (shell.passagesOpen) return shell.closePassages;
      if (shell.citedOpen) return shell.closeCited;
      if (shell.rightOpen) return shell.closeSources;
      if (shell.phonePage != null) return shell.closePhonePage;
      // The workspace's pages step back: a document's text, a page, then what they opened over.
      if (shell.pane == Pane.files) {
        if (scope.files.reading != null) return () => closeDocText(scope);
        if (shell.workspacePage != null) {
          return () => shell.showWorkspacePage(null);
        }
        return () => shell.showPane(Pane.chats);
      }
      if (shell.chatOpen) return shell.closeChat;
      return null;
    }

    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) {
        final files = shell.pane == Pane.files;
        final chatShown = shell.chatOpen && !files;
        final homeCovered =
            shell.chatOpen ||
            files ||
            shell.phonePage != null ||
            shell.settingsOpen;
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
                        // The Chats tab, kept while anything covers it.
                        Positioned.fill(
                          child: Offstage(
                            offstage: homeCovered,
                            child: TickerMode(
                              enabled: !homeCovered,
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: ChatsTab()),
                                  HomeTabBar(),
                                ],
                              ),
                            ),
                          ),
                        ),
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
                                  child: const ChatView(),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (files)
                          Positioned.fill(
                            child: ColoredBox(
                              color: t.bg,
                              child: const WorkspacePages(),
                            ),
                          ),
                        if (shell.phonePage case final page?)
                          Positioned.fill(
                            child: switch (page) {
                              PhonePage.upcoming => const UpcomingPage(),
                            },
                          ),
                        // The sheet's own scrim closes it.
                        if (shell.rightOpen) Positioned.fill(child: right),
                        // A deleted chat is put back from over the chat or the Chats tab.
                        if (!shell.settingsOpen)
                          _PhoneUndo(overTabs: shell.atHome),
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
    );
  }
}

/// Undo for a chat just deleted, over the chat or, with [overTabs], over the bar of tabs, while
/// it can be put back.
class _PhoneUndo extends StatelessWidget {
  const _PhoneUndo({required this.overTabs});

  final bool overTabs;

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
              bottom: overTabs ? 104 : 96,
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
