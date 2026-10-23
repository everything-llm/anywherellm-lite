import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/browser_tabs.dart';
import '../../core/copy.dart';
import '../../core/server_models.dart';
import '../../core/skill_pages.dart';
import '../app_scope.dart';
import '../home.dart';
import '../icons.dart';
import '../settings/rows.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../toolkit_card.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/phone_page.dart';
import '../widgets/scroll_fades.dart';
import '../widgets/sheet.dart';
import '../widgets/tappable.dart';
import '../widgets/ticking.dart';

/// The agent's browser's open tabs, from the shelf's Browser row, in a sheet as the
/// LiteBrowserSheet board draws it: Close first and Browser over how many tabs are open, then
/// each workspace's tabs in a tile under its name and when its browser closes, soonest first
/// ([tabGroups]). A row names the chat whose answers read here link to the tab, or else the
/// page's title, over its host and who has it, and opens the tab in [BrowserSheet]: over that
/// chat with the bar that messages the agent, or, where no chat read here links to it, without
/// the bar. It reads the tabs and their states afresh as it opens, and counts down while it
/// shows.
class TabsSheet extends StatefulWidget {
  const TabsSheet({super.key});

  @override
  State<TabsSheet> createState() => _TabsSheetState();
}

class _TabsSheetState extends State<TabsSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).toolkit.readTabs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    void close() => scope.shell.closePopup(Popup.browserTabs);
    return Ticking(
      builder: (context) => ListenableBuilder(
        listenable: Listenable.merge([scope.toolkit, scope.chat]),
        builder: (context, _) {
          final toolkit = scope.toolkit;
          final now = clock.now();
          final groups = tabGroups(
            toolkit.tabs ?? const [],
            toolkit.tabState,
            now,
          );
          final count = groups.fold(0, (n, group) => n + group.tabs.length);
          return SheetFrame(
            title: 'Browser',
            bare: true,
            padding: EdgeInsets.zero,
            onClose: close,
            header: _Header(
              count == 0
                  ? 'No tabs open'
                  : '${plural(count, 'tab', 'tabs')} open'
                        '${count > 1 ? ' · soonest to close first' : ''}',
              onClose: close,
            ),
            child: ScrollFades(
              color: t.ground,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (groups.isEmpty) const _NoTabs(),
                    for (final group in groups) ...[
                      _GroupHeading(
                        scope.chat.workspaceOf(group.workspace)?.name ??
                            group.workspace,
                        closesIn(group.closes, now),
                      ),
                      const SizedBox(height: 8),
                      _tabs(scope, group),
                      const SizedBox(height: 20),
                    ],
                    _Footnote(
                      vault: toolkit.pagesFound.contains(SkillPage.vault),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// [group]'s tabs in a tile, each named by the chat that links to it when one read here does.
  Widget _tabs(AppScope scope, TabGroup group) {
    final chats = scope.chat.chatsLinking(group.workspace, {
      for (final (tab, _) in group.tabs) tab.path,
    });
    return FieldCard([
      for (final (tab, state) in group.tabs)
        _TabRow(
          tab,
          state,
          chat: chats[tab.path],
          failed: scope.toolkit.tabFailed(tab.path),
        ),
    ]);
  }
}

/// The sheet's header under its drag handle: Close, then Browser over [summary].
class _Header extends StatelessWidget {
  const _Header(this.summary, {required this.onClose});

  final String summary;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconBtn.header('close', tooltip: 'Close', onPressed: onClose),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text('Browser', style: Type.title(t.ink)),
                ),
                Text(summary, style: Type.note(t.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A workspace's [name] over its tabs, and when its browser [closes] at the end, under the name
/// when both do not fit on one line.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading(this.name, this.closes);

  final String name;
  final String closes;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      header: true,
      label: '$name, $closes',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FieldCard.inset),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.caption(t.ink),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon('clock', size: IconSize.small, color: t.ink),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    capitalized(closes),
                    style: Type.note(t.ink).copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A tab: its [chat], or its page's title, over its host and who has it. A tap opens it.
class _TabRow extends StatelessWidget {
  const _TabRow(
    this.tab,
    this.state, {
    required this.chat,
    required this.failed,
  });

  final OpenTab tab;
  final TabState? state;
  final Thread? chat;

  /// Whether its state could not be read.
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final state = this.state;
    final name = chat?.name ?? state?.title ?? state?.host ?? 'A tab';
    final (line, who) = switch (state) {
      _ when failed => ('Could not read the tab', null),
      null => ('Reading…', null),
      TabState(:final host, :final mine) => (
        host ?? '',
        mine ? 'You have it' : 'Agent has it',
      ),
    };
    final heard = [name, if (line.isNotEmpty) line, ?who?.toLowerCase()];
    return NavRow(
      title: name,
      heard: '${heard.join(', ')}. Open the tab',
      lead: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: t.sunken,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: AppIcon('globe', size: IconSize.medium, color: t.ink),
      ),
      aboutSpan: TextSpan(
        children: [
          TextSpan(text: line),
          if (who != null) ...[
            if (line.isNotEmpty) const TextSpan(text: ' · '),
            TextSpan(
              text: who,
              style: TextStyle(
                fontWeight: state?.mine ?? false
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
      onTap: () => _open(context),
    );
  }

  /// Opens the tab: over its chat, opened first, with the bar that messages its agent, or, with
  /// no chat, without the bar.
  Future<void> _open(BuildContext context) async {
    final scope = AppScope.of(context);
    final server = scope.settings.connection?.uri;
    if (server == null) return;
    final url = server.resolve(tab.path);
    if (chat case final chat?) {
      await openThread(scope, tab.workspace, chat);
    }
    scope.shell.openBrowser(url, inChat: chat != null);
  }
}

/// What the sheet says with no tab open.
class _NoTabs extends StatelessWidget {
  const _NoTabs();

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No tabs open.', style: Type.body(t.ink)),
          const SizedBox(height: 4),
          Text(
            'A tab opens when the agent browses in a chat.',
            style: Type.note(t.ink),
          ),
        ],
      ),
    );
  }
}

/// Under the tabs: where they come from and, while the [vault] is set up, that the saved logins
/// are in the Vault, a link that opens it.
class _Footnote extends StatelessWidget {
  const _Footnote({required this.vault});

  /// Whether the Vault is set up.
  final bool vault;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FieldCard.inset),
      child: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Tabs from chats in every workspace.'),
            if (vault) ...[
              const TextSpan(text: ' Saved logins are in the '),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Tappable(
                  label: 'Vault',
                  onTap: () => openListedPage(
                    context,
                    SkillPage.vault,
                    SkillPage.vault.listing!,
                  ),
                  child: Text(
                    'Vault',
                    style: Type.note(t.accent).copyWith(
                      decoration: TextDecoration.underline,
                      decorationColor: t.accent,
                    ),
                  ),
                ),
              ),
              const TextSpan(text: '.'),
            ],
          ],
        ),
        style: Type.note(t.ink),
      ),
    );
  }
}
