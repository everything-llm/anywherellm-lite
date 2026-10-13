import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'apps/app_screen.dart';
import 'apps/app_sheets.dart';
import 'apps/apps_tab.dart';
import 'chat/chat_view.dart';
import 'chat/cited_sources.dart';
import 'chat/gallery.dart';
import 'chat_sheet.dart';
import 'chat/passages_sheet.dart';
import 'files/workspace_pages.dart';
import 'settings/settings_dialog.dart';
import 'share/share_sheet.dart';
import 'shelf.dart';
import 'share/shared_item.dart';
import 'home.dart';
import 'workspace_sheets.dart';
import 'sources/sources_panel.dart';
import 'upcoming.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'widgets/basics.dart';

/// The window: the bar of tabs at its foot, always, but while the keyboard is up and on the
/// first run's welcome, and above it the home, the Chats tab or the Apps tab; the chat over it;
/// the workspace's pages or Upcoming over those; Settings, its list or a page, over them all;
/// and the sheets and popups over the whole window, the bar too. Esc and Back close the
/// topmost thing open: the popup, Settings' page, the sheet, Upcoming, the workspace's pages a
/// step at a time, then the chat.
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
      if (shell.shelfOpen) return shell.closeShelf;
      if (shell.app != null) return shell.appBack;
      if (shell.passagesOpen) return shell.closePassages;
      if (shell.citedOpen) return shell.closeCited;
      if (shell.rightOpen) return shell.closeSources;
      if (shell.upcomingOpen) return shell.closeUpcoming;
      // The workspace's pages step back: a document's text, a page, then what they opened over.
      if (shell.pane == Pane.files) {
        if (scope.files.reading != null) return () => closeDocText(scope);
        if (shell.workspacePage != null) {
          return () => shell.showWorkspacePage(null);
        }
        return () => shell.showPane(Pane.chats);
      }
      if (shell.chatOpen) return shell.closeChat;
      // Back from the Apps tab goes to the Chats tab, as from any tab but the first.
      if (shell.tab == HomeTab.apps) return () => shell.showTab(HomeTab.chats);
      return null;
    }

    return ListenableBuilder(
      listenable: Listenable.merge([shell, scope.apps]),
      builder: (context, _) {
        final files = shell.pane == Pane.files;
        final app = shell.app;
        // An app's sheet shows over the chat or the tab; its data, full screen, covers them.
        final appData = app != null && shell.appDataOnly;
        final chatShown = shell.chatOpen && !files && !appData;
        // The first run's welcome stands alone, since no tab has anything to show yet.
        final tabs = !(shell.settingsOpen && !scope.settings.configured);
        final homeCovered =
            shell.chatOpen ||
            files ||
            shell.upcomingOpen ||
            shell.settingsOpen ||
            appData;
        // The Apps tab shows only while the apps server is there.
        final appsTab =
            shell.tab == HomeTab.apps && scope.apps.available == true;
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: Stack(
                                  children: [
                                    // The Chats tab, kept while anything covers it.
                                    Positioned.fill(
                                      child: Offstage(
                                        offstage: homeCovered,
                                        child: TickerMode(
                                          enabled: !homeCovered,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              // Kept while Apps shows, with its search.
                                              Offstage(
                                                offstage: appsTab,
                                                child: const ChatsTab(),
                                              ),
                                              if (appsTab) const AppsTab(),
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
                                    // The Chats tab as a shelf from the left over the chat.
                                    if (shell.shelfOpen && chatShown)
                                      const Positioned.fill(
                                        child: ChatsShelf(),
                                      ),
                                    if (files)
                                      Positioned.fill(
                                        child: ColoredBox(
                                          color: t.bg,
                                          child: const WorkspacePages(),
                                        ),
                                      ),
                                    if (shell.upcomingOpen)
                                      const Positioned.fill(
                                        child: UpcomingPage(),
                                      ),
                                    // An app's data, full screen as a page is.
                                    if (app != null && appData)
                                      Positioned.fill(
                                        child: AppScreen(
                                          app,
                                          key: ValueKey(app),
                                        ),
                                      ),
                                    // A deleted chat is put back from over the chat or the Chats tab.
                                    if (!shell.settingsOpen)
                                      _PhoneUndo(overTabs: shell.atHome),
                                    if (shell.settingsOpen)
                                      const Positioned.fill(
                                        child: SettingsDialog(),
                                      ),
                                  ],
                                ),
                              ),
                              if (tabs) const _TabsUnlessTyping(),
                            ],
                          ),
                        ),
                        // The sheet's own scrim closes it.
                        if (shell.rightOpen) Positioned.fill(child: right),
                        // An app in a sheet, over the chat or the tab it was opened from.
                        if (app != null && !appData)
                          Positioned.fill(
                            child: AppScreen(app, key: ValueKey(app)),
                          ),
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
                                if (popup case final AppSheet sheet)
                                  Positioned.fill(
                                    child: AppSheetView(
                                      sheet,
                                      key: ObjectKey(sheet),
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

/// Undo for a chat just deleted, over the chat's composer or, with [overTabs], just over the bar
/// of tabs, while it can be put back.
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
              bottom: overTabs ? 30 : 96,
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
/// keyboard's animation rebuilds this and not [child]; [_Typing] says whether it is up.
class _AboveKeyboard extends StatelessWidget {
  const _AboveKeyboard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: _Typing(typing: inset > 0, child: child),
      ),
    );
  }
}

/// Whether the keyboard is up, for what [_AboveKeyboard] holds, which no longer sees its inset.
/// Only a change of it rebuilds those that read it, not each frame of the keyboard's rise.
class _Typing extends InheritedWidget {
  const _Typing({required this.typing, required super.child});

  final bool typing;

  @override
  bool updateShouldNotify(_Typing old) => typing != old.typing;
}

/// The bar of tabs, put away while the keyboard is up, so the field typed in keeps the room.
class _TabsUnlessTyping extends StatelessWidget {
  const _TabsUnlessTyping();

  @override
  Widget build(BuildContext context) {
    final typing =
        context.dependOnInheritedWidgetOfExactType<_Typing>()?.typing ?? false;
    return Offstage(offstage: typing, child: const HomeTabBar());
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
