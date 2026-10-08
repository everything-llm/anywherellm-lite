import 'package:flutter/material.dart';

import '../../core/prefs.dart';
import '../../core/providers.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/phone_page.dart';
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
import 'server_page.dart';
import 'settings_pages.dart';

/// Settings, drawn over the app by the shell: a list of pages beside the page chosen, or, where
/// they do not fit side by side, the list and then the page with a way back.
///
/// On a [phone] it is a page over the window instead: a back arrow and the title, then the list
/// in two groups, This app and AnythingLLM, whose one row opens the Server page, which lists the
/// server's pages.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.sideBySide,
    this.phone = false,
  });

  /// Whether the list of pages sits beside the page, as the shell lays it out.
  final bool sideBySide;
  final bool phone;

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
    if (widget.phone) {
      return Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: 'Settings',
        child: FocusScope(
          autofocus: true,
          child: ColoredBox(
            color: t.bg,
            child: ListenableBuilder(
              listenable: Listenable.merge([scope.shell, scope.settings]),
              builder: (context, _) => _PhoneFrame(
                page: scope.shell.settingsPage,
                configured: scope.settings.configured,
              ),
            ),
          ),
        ),
      );
    }
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

/// A phone's Settings: the list, or a page, under a back arrow and the title.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.page, required this.configured});

  /// The page shown, or null for the list.
  final SettingsPage? page;
  final bool configured;

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    var page = this.page;
    if (page != null && page.needsServer && !configured) {
      page = SettingsPage.connection;
    }
    final back = switch (page) {
      null => 'Back to the chat',
      final page => 'Back to ${page.phoneParent?.label ?? 'Settings'}',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhonePageHeader(
          title: page?.label ?? 'Settings',
          back: back,
          onBack: () => shell.settingsBack(phone: true),
        ),
        Expanded(
          child: page == null
              ? const _PhoneNav()
              : _PageView(page, wide: false, phone: true),
        ),
      ],
    );
  }
}

/// A phone's list of Settings: This app's pages, each with what it is set to, and once a server
/// is saved, AnythingLLM's Server row.
class _PhoneNav extends StatelessWidget {
  const _PhoneNav();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final connection = scope.settings.connection;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.prefs, scope.system]),
      builder: (context, _) {
        final prefs = scope.prefs.prefs;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          children: [
            const SectionLabel('This app'),
            const SizedBox(height: 6),
            FieldCard([
              NavRow(
                title: SettingsPage.connection.label,
                about: connection == null
                    ? 'Not connected'
                    : 'Connected to ${connection.uri.host}',
                onTap: () => shell.showSettingsPage(SettingsPage.connection),
              ),
              NavRow(
                title: SettingsPage.appearance.label,
                about: switch (prefs.theme) {
                  ThemePref.system => 'System theme',
                  ThemePref.light => 'Light theme',
                  ThemePref.dark => 'Dark theme',
                },
                onTap: () => shell.showSettingsPage(SettingsPage.appearance),
              ),
              NavRow(
                title: SettingsPage.chat.label,
                about: chatSummary(scope),
                onTap: () => shell.showSettingsPage(SettingsPage.chat),
              ),
            ]),
            if (connection != null) ...[
              const SizedBox(height: 18),
              const SectionLabel('AnythingLLM'),
              const SizedBox(height: 6),
              FieldCard([
                NavRow(
                  title: SettingsPage.server.label,
                  about: serverSummary(scope.system),
                  onTap: () => shell.showSettingsPage(SettingsPage.server),
                ),
              ]),
            ],
          ],
        );
      },
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
        if (!page.phoneOnly &&
            (configured || !page.needsServer) &&
            (all || page.essential))
          page,
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
  const _PageView(this.page, {required this.wide, this.phone = false});

  final SettingsPage page;
  final bool wide;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final server = scope.settings.connection?.withPassword(null);
    final firstRun = page == SettingsPage.connection && server == null;
    return SingleChildScrollView(
      key: ValueKey(page),
      padding: wide
          ? const EdgeInsets.fromLTRB(32, 24, 32, 40)
          : phone
          ? const EdgeInsets.fromLTRB(20, 12, 20, 32)
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
              // A phone's first run says what to do in its own words.
              if (!(phone && firstRun)) ...[
                const SizedBox(height: 6),
                Text(
                  phone && page == SettingsPage.connection
                      ? 'How this phone reaches AnythingLLM.'
                      : page.about,
                  style: Type.sans(15, color: t.ink2, height: 1.5),
                ),
                const SizedBox(height: 20),
              ],
              KeyedSubtree(key: ValueKey((page, server)), child: _body(page)),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _body(SettingsPage page) => switch (page) {
    SettingsPage.connection => const ConnectionPage(),
    SettingsPage.server => const ServerPage(),
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
