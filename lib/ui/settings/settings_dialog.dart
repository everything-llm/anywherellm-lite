import 'package:flutter/material.dart';

import '../../core/providers.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/segmented.dart';
import '../widgets/tappable.dart';
import 'chats_page.dart';
import 'connection_page.dart';
import 'device_pages.dart';
import 'embeds_page.dart';
import 'json_page.dart';
import 'privacy_page.dart';
import 'provider_page.dart';
import 'rows.dart';
import 'settings_pages.dart';

/// Settings, drawn over the app by the shell: a list of pages beside the page chosen, or, where
/// they do not fit side by side, the list and then the page with a way back.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key, required this.sideBySide});

  /// Whether the list of pages sits beside the page, as the shell lays it out.
  final bool sideBySide;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  /// Reads the server's settings afresh each time Settings opens; its pages then share them.
  @override
  void initState() {
    super.initState();
    final scope = AppScope.of(context);
    if (scope.settings.configured) scope.system.readSettings();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sideBySide = widget.sideBySide;
    final t = Tokens.of(context);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Settings',
      child: FocusScope(
        autofocus: true,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 980, maxHeight: 780),
          margin: EdgeInsets.all(sideBySide ? 20 : 12),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: t.panel2,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: t.shadow.withValues(alpha: 0.35),
                // Flutter blurs a radius more than CSS does; 51 here is CSS's 60.
                blurRadius: 51,
                spreadRadius: -12,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: ListenableBuilder(
            listenable: Listenable.merge([scope.shell, scope.settings]),
            builder: (context, _) => _Frame(wide: sideBySide),
          ),
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.wide});

  final bool wide;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final configured = scope.settings.configured;
    final all = shell.allSettings && configured;
    final pages = [
      for (final page in SettingsPage.values)
        if ((configured || !page.needsServer) && (all || page.essential)) page,
    ];
    var page = shell.settingsPage;
    if (page != null && !pages.contains(page)) page = SettingsPage.connection;
    if (wide) page ??= SettingsPage.connection;
    final nav = _Nav(
      pages: pages,
      current: page,
      all: all,
      canShowAll: configured,
      wide: wide,
    );
    final t = Tokens.of(context);
    final rule = Divider(height: 1, thickness: 1, color: t.line);
    if (wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Header(),
          rule,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: Sizes.settingsNav, child: nav),
                VerticalDivider(width: 1, thickness: 1, color: t.line),
                Expanded(child: _PageView(page!, wide: true)),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(page: page),
        rule,
        Expanded(child: page == null ? nav : _PageView(page, wide: false)),
      ],
    );
  }
}

/// Settings' title and Done, or, over a page where the list is not beside it, a way back to the
/// list and the page's name.
class _Header extends StatelessWidget {
  const _Header({this.page});

  final SettingsPage? page;

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    final t = Tokens.of(context);
    final page = this.page;
    return Padding(
      padding: EdgeInsets.fromLTRB(page == null ? 24 : 10, 16, 24, 16),
      child: Row(
        children: [
          if (page != null) ...[
            IconBtn(
              'back',
              tooltip: 'All settings',
              onPressed: () => shell.showSettingsPage(null),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                page?.label ?? 'Settings',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.serif(28, color: t.ink, letterSpacing: -0.4),
              ),
            ),
          ),
          const SizedBox(width: 12),
          AppButton('Done', primary: true, onPressed: shell.closeSettings),
        ],
      ),
    );
  }
}

/// The pages, under their groups, with the switch between the essentials and every page.
class _Nav extends StatelessWidget {
  const _Nav({
    required this.pages,
    required this.current,
    required this.all,
    required this.canShowAll,
    required this.wide,
  });

  final List<SettingsPage> pages;
  final SettingsPage? current;
  final bool all;
  final bool canShowAll;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    final t = Tokens.of(context);
    SettingsGroup? group;
    return ColoredBox(
      color: wide ? t.side : t.panel2,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
        children: [
          if (canShowAll)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Segmented<bool>(
                options: const [(false, 'Essentials'), (true, 'All settings')],
                value: all,
                onChanged: shell.showAllSettings,
              ),
            ),
          for (final page in pages) ...[
            if (page.group != group)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 16, 10, 4),
                child: SectionLabel((group = page.group).label),
              ),
            _NavItem(page, current: page == current, wide: wide),
          ],
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.page, {required this.current, required this.wide});

  final SettingsPage page;
  final bool current;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tappable(
        label: page.label,
        selected: current,
        onTap: () => shell.showSettingsPage(page),
        radius: BorderRadius.circular(8),
        color: current ? t.sel : null,
        child: Container(
          constraints: BoxConstraints(minHeight: wide ? 36 : 48),
          padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  page.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(
                    14,
                    weight: current ? FontWeight.w600 : FontWeight.w400,
                    color: t.ink,
                  ),
                ),
              ),
              if (!wide) AppIcon('chevron', size: IconSize.xs, color: t.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// [page]'s title, what it is for, and its settings, scrolling. A new server builds it afresh.
class _PageView extends StatelessWidget {
  const _PageView(this.page, {required this.wide});

  final SettingsPage page;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final server = scope.settings.connection?.withPassword(null);
    return SingleChildScrollView(
      key: ValueKey(page),
      padding: wide
          ? const EdgeInsets.fromLTRB(32, 24, 32, 40)
          : const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                Semantics(
                  header: true,
                  child: Text(
                    page.label,
                    style: Type.serif(
                      32,
                      color: t.ink,
                      height: 1.15,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                page.about,
                style: Type.sans(15, color: t.ink2, height: 1.5),
              ),
              const SizedBox(height: 20),
              KeyedSubtree(key: ValueKey((page, server)), child: _body(page)),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _body(SettingsPage page) => switch (page) {
    SettingsPage.connection => const ConnectionPage(),
    SettingsPage.appearance => const AppearancePage(),
    SettingsPage.chat => const ChatPage(),
    SettingsPage.chatModel => const ProviderPage([
      chatProviders,
    ], fieldsNote: 'These fields change with the provider.'),
    SettingsPage.searchModel => const ProviderPage(
      [embedderProviders],
      before: [SearchModelWarning()],
    ),
    SettingsPage.storage => const ProviderPage(
      [vectorProviders],
      lead: [StoredPassages()],
    ),
    SettingsPage.images => const ProviderPage([imageProviders]),
    SettingsPage.voice => const ProviderPage(
      [speechToTextProviders, textToSpeechProviders],
      after: [
        PageNote(
          'Read aloud and dictation in AnywhereLLM use the device\'s own engines, whatever '
          'is set here.',
        ),
      ],
    ),
    SettingsPage.transcription => const ProviderPage([transcriptionProviders]),
    SettingsPage.chats => const ChatsPage(),
    SettingsPage.embeds => const EmbedsPage(),
    SettingsPage.privacy => const PrivacyPage(),
    SettingsPage.json => const JsonPage(),
  };
}
