import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/apps.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../settings/rows.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/min_height.dart';
import '../widgets/phone_page.dart';
import '../widgets/sheet.dart';
import '../widgets/tappable.dart';
import '../workspace_switcher.dart';
import 'app_sheets.dart';

/// The Apps tab, where the apps server is there: Apps over the open workspace's name, which
/// opens the Workspaces sheet, then the workspace's apps in one card, each with its kind, its
/// summary and when it last changed, and a More button that opens its menu. An app tapped opens
/// full screen. The apps are read each time the tab shows.
class AppsTab extends StatefulWidget {
  const AppsTab({super.key});

  @override
  State<AppsTab> createState() => _AppsTabState();
}

class _AppsTabState extends State<AppsTab> {
  @override
  void initState() {
    super.initState();
    final apps = AppScope.of(context).apps;
    // A read tells the controller's listeners at once, so it waits for the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(apps.want());
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return Semantics(
      container: true,
      label: 'Apps',
      child: MinHeight(
        min: Sizes.panelMin,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Title(),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([scope.apps, scope.chat]),
                builder: (context, _) {
                  final apps = scope.apps.apps;
                  final now = DateTime.now();
                  return ListView(
                    padding: Sizes.pagePadding,
                    children: [
                      if (scope.apps.problem case final problem?) ...[
                        AlertBox(
                          AlertKind.warn,
                          'Could not read the apps',
                          text: problem,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (apps == null)
                        if (scope.apps.problem == null)
                          Text('Reading…', style: Type.sans(14, color: t.muted))
                        else
                          const SizedBox.shrink()
                      else if (apps.isEmpty)
                        const FieldCard([
                          CardNote('No apps in this workspace yet.'),
                        ])
                      else
                        FieldCard([
                          for (final app in apps) _AppRow(app, now: now),
                        ]),
                      if (apps != null && apps.isEmpty) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FieldCard.inset,
                          ),
                          child: Text(
                            'Ask the agent in a chat to make one, such as a '
                            'list or a tracker.',
                            style: Type.note(t.muted),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Apps at 26, over the open workspace's name and a chevron, which open the Workspaces sheet.
class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.chat, shell.popup]),
      builder: (context, _) {
        final active = scope.chat.active;
        return PopupSheet(
          open: shell.menuOpen,
          onClose: () => shell.closePopup(Popup.workspaces),
          title: 'Workspaces',
          sheet: (context) => SingleChildScrollView(
            child: WorkspaceMenu(
              onCreate: () => shell.togglePopup(WorkspaceSheet.create),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text('Apps', style: TabTitle.style(t.ink)),
                ),
                Tappable(
                  label: active == null
                      ? 'Workspaces'
                      : 'Workspace: ${active.name}. Switch workspace',
                  expanded: shell.menuOpen,
                  radius: BorderRadius.circular(Sizes.small),
                  onTap: () => shell.togglePopup(Popup.workspaces),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 32),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 4,
                      children: [
                        Flexible(
                          child: Text(
                            active?.name ?? 'No workspace yet',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Type.sans(14, color: t.muted),
                          ),
                        ),
                        AppIcon('down', size: IconSize.xs, color: t.muted),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// An app in the Apps tab: its title over its kind, summary and when it last changed, and a
/// More button that opens its menu. Tapped, it opens full screen.
class _AppRow extends StatelessWidget {
  const _AppRow(this.app, {required this.now});

  final ServerApp app;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    final t = Tokens.of(context);
    final about = app.about(now);
    return Padding(
      padding: const EdgeInsets.only(left: FieldCard.inset, right: 8),
      child: Row(
        children: [
          Expanded(
            child: Tappable(
              label: '${app.title}, $about',
              onTap: () => shell.openApp(app.ref),
              child: Container(
                constraints: const BoxConstraints(minHeight: Sizes.cardRow),
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 2,
                  children: [
                    Text(
                      app.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.sans(
                        16,
                        weight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                    Text(
                      about,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.sans(
                        13,
                        color: app.error == null ? t.muted : t.badfg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconBtn(
            'more',
            tooltip: 'Open, rename or delete ${app.title}',
            box: 44,
            size: IconSize.small,
            onPressed: () => openAppMenu(shell, app.ref),
          ),
        ],
      ),
    );
  }
}
