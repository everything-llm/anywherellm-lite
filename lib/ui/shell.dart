import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_scope.dart';
import 'chat/chat_view.dart';
import 'files/files_view.dart';
import 'layout.dart';
import 'settings/settings_dialog.dart';
import 'sidebar.dart';
import 'sources/sources_panel.dart';
import 'state/shell_controller.dart';
import 'tokens.dart';
import 'widgets/rise.dart';

/// The window: sidebar, chat and Sources, arranged for the width they have, with Settings over
/// them when it is open.
///
/// Below 820 the sidebar is a drawer from the left; below 1120 Sources is a drawer from the
/// right. Esc and Back close the topmost thing open: Settings, then a drawer.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final t = Tokens.of(context);
    final duration = motion(context, const Duration(milliseconds: 250));

    bool closeTop() {
      if (shell.settingsOpen) {
        shell.closeSettings();
      } else if (shell.sideOpen) {
        shell.closeSide();
      } else {
        return false;
      }
      return true;
    }

    return LayoutBuilder(
      builder: (context, box) {
        final screen = ScreenClass.of(box.maxWidth);
        final sourcesInline = ScreenClass.sourcesInline(box.maxWidth);
        shell.fit(sourcesInline: sourcesInline);
        return ListenableBuilder(
          listenable: shell,
          builder: (context, _) {
            final sideDrawer = screen.sidebarDrawer && shell.sideOpen;
            final files = shell.pane == Pane.files;
            final sourcesDrawer = !sourcesInline && shell.sourcesOpen;
            return PopScope(
              canPop: !shell.settingsOpen && !shell.sideOpen && !sourcesDrawer,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop && !closeTop()) shell.closeSources();
              },
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () {
                    if (!closeTop() && sourcesDrawer) shell.closeSources();
                  },
                },
                child: Focus(
                  autofocus: true,
                  // InkWell needs a Material above it, and the shell has no Scaffold.
                  child: Material(
                    color: t.bg,
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            if (screen.sidebarInline) const Sidebar(),
                            Expanded(
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
                                    FilesView(showMenu: screen.sidebarDrawer),
                                ],
                              ),
                            ),
                            if (sourcesInline)
                              AnimatedContainer(
                                duration: duration,
                                curve: Curves.easeOut,
                                width: shell.sourcesOpen ? Sizes.sources : 0,
                                child: ClipRect(
                                  child: OverflowBox(
                                    alignment: Alignment.centerLeft,
                                    minWidth: Sizes.sources,
                                    maxWidth: Sizes.sources,
                                    child: _Hidden(
                                      hidden: !shell.sourcesOpen,
                                      child: const SourcesPanel(),
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
                            width: Sizes.sources,
                            duration: duration,
                            child: const SourcesPanel(),
                          ),
                        if (shell.settingsOpen) ...[
                          _Scrim(onTap: shell.closeSettings),
                          const Center(child: SettingsDialog()),
                        ],
                      ],
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
