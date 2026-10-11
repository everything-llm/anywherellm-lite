import 'package:flutter/material.dart';

import '../../core/prefs.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../links.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/phone_page.dart';
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
import 'settings_search.dart';

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
      final page => 'Back to ${page.parent?.label ?? 'Settings'}',
    };
    // A first run opens on its welcome alone, with no bar over it; Back still closes it.
    if (page == SettingsPage.connection && !configured) {
      return const _PageView(SettingsPage.connection, wide: false, phone: true);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhonePageHeader(
          title: page?.label ?? 'Settings',
          back: back,
          onBack: shell.settingsBack,
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
    var page = shell.settingsPage;
    if (page != null && page.needsServer && !configured) {
      page = SettingsPage.connection;
    }
    if (wide) page ??= SettingsPage.connection;
    final nav = _Nav(current: page, configured: configured, wide: wide);
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
              tooltip: page.parent == null
                  ? 'All settings'
                  : 'Back to ${page.parent!.label}',
              onPressed: shell.settingsBack,
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

/// The list of Settings: a search over the pages, then This app's pages and, once a server is
/// saved, the Server page, with the page open beneath it when it is one of the server's. A
/// search lists the pages it finds in their place.
class _Nav extends StatefulWidget {
  const _Nav({
    required this.current,
    required this.configured,
    required this.wide,
  });

  final SettingsPage? current;
  final bool configured;
  final bool wide;

  @override
  State<_Nav> createState() => _NavState();
}

class _NavState extends State<_Nav> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final t = Tokens.of(context);
    final current = widget.current;
    final wide = widget.wide;
    Widget item(
      String label, {
      SettingsPage? page,
      String? hint,
      double indent = 10,
      VoidCallback? onTap,
    }) => _NavItem(
      label,
      hint: hint,
      current: page != null && page == current,
      indent: indent,
      wide: wide,
      onTap:
          onTap ??
          () {
            _search.clear();
            shell.showSettingsPage(page);
          },
    );
    Widget head(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 4),
      child: SectionLabel(label),
    );
    return ColoredBox(
      color: wide ? t.side : t.panel2,
      child: ListenableBuilder(
        listenable: _search,
        builder: (context, _) {
          final query = _search.text.trim();
          final hits = searchSettings(query, configured: widget.configured);
          return ListView(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 14),
            children: [
              _SearchBox(_search),
              if (query.isNotEmpty) ...[
                head(hits.isEmpty ? 'Nothing matches' : 'Results'),
                for (final hit in hits)
                  if (hit.page case final page?)
                    item(page.label, page: page, hint: hit.field)
                  else
                    item(
                      hit.label,
                      hint: 'In the browser',
                      onTap: () => openServerPage(context),
                    ),
              ] else ...[
                head('This app'),
                for (final page in const [
                  SettingsPage.connection,
                  SettingsPage.appearance,
                  SettingsPage.chat,
                ])
                  item(page.label, page: page),
                if (widget.configured) ...[
                  head('AnythingLLM'),
                  item(SettingsPage.server.label, page: SettingsPage.server),
                  if (current != null && current.parent != null)
                    item(current.label, page: current, indent: 22),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The search over Settings' pages: a 40 px field with the search icon before the text.
class _SearchBox extends StatelessWidget {
  const _SearchBox(this.controller);

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: t.panel,
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            AppIcon('search', size: IconSize.small, color: t.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                label: 'Search settings',
                textField: true,
                child: TextField(
                  controller: controller,
                  autocorrect: false,
                  style: Type.sans(14, color: t.ink),
                  cursorColor: t.accent,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Search settings',
                    hintStyle: Type.sans(14, color: t.fade),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(
    this.label, {
    required this.hint,
    required this.current,
    required this.indent,
    required this.wide,
    required this.onTap,
  });

  final String label;

  /// The field a search matched, or where the page opens, small at the row's end.
  final String? hint;
  final bool current;

  /// How far in the label starts: more for the page open under Server.
  final double indent;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tappable(
        label: [label, ?hint].join(', '),
        selected: current,
        onTap: onTap,
        radius: BorderRadius.circular(8),
        color: current ? t.sel : null,
        child: Container(
          constraints: BoxConstraints(minHeight: wide ? 36 : 48),
          padding: EdgeInsets.fromLTRB(indent, 0, 8, 0),
          child: Row(
            spacing: 8,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(
                    14,
                    weight: current ? FontWeight.w600 : FontWeight.w400,
                    color: t.ink,
                  ),
                ),
              ),
              if (hint case final hint?)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(12, color: t.muted),
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
          : phone && firstRun
          ? const EdgeInsets.fromLTRB(24, 72, 24, 24)
          : phone
          ? const EdgeInsets.fromLTRB(20, 14, 20, 32)
          : const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                if (page.parent case final parent?) _BackLink(parent),
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
              // A phone's first run says what to do in its own words, and a phone's
              // Appearance and Chat need no line, as the design canvas draws them.
              if (phone && (firstRun || page == SettingsPage.chat))
                const SizedBox.shrink()
              else if (phone && page == SettingsPage.appearance)
                const SizedBox(height: 2)
              else if (phone) ...[
                Text(switch (page) {
                  SettingsPage.connection =>
                    'How this phone reaches AnythingLLM.',
                  SettingsPage.server => 'What AnythingLLM runs with. Each row opens the page that changes it.',
                  _ => page.about,
                }, style: Type.sans(14.5, color: t.ink2, height: 1.5)),
                const SizedBox(height: 14),
              ] else ...[
                const SizedBox(height: 6),
                Text(
                  page.about,
                  style: Type.sans(15, color: t.ink2, height: 1.5),
                ),
                const SizedBox(height: 20),
              ],
              KeyedSubtree(
                key: ValueKey((page, server)),
                child: _body(page, phone: phone),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _body(SettingsPage page, {required bool phone}) =>
      switch (page) {
        SettingsPage.connection => const ConnectionPage(),
        SettingsPage.server => ServerPage(phone: phone),
        SettingsPage.appearance => const AppearancePage(),
        SettingsPage.chat => const ChatPage(),
        SettingsPage.chatModel => ProviderPage(
          providerPages[page]!,
          fieldsNote: 'These fields change with the provider.',
        ),
        SettingsPage.searchModel => ProviderPage(
          providerPages[page]!,
          before: const [SearchModelWarning()],
        ),
        SettingsPage.storage => ProviderPage(
          providerPages[page]!,
          lead: const [StoredPassages()],
        ),
        SettingsPage.voice => ProviderPage(
          providerPages[page]!,
          after: const [
            PageNote(
              'Read aloud and dictation in AnywhereLLM use the device\'s own engines, whatever '
              'is set here.',
            ),
          ],
        ),
        SettingsPage.images ||
        SettingsPage.transcription => ProviderPage(providerPages[page]!),
        SettingsPage.chats => const ChatsPage(),
        SettingsPage.embeds => const EmbedsPage(),
        SettingsPage.privacy => const PrivacyPage(),
        SettingsPage.json => const JsonPage(),
      };
}

/// A link over a server page's title back to the page it is reached from: a chevron turned
/// back, then the page's name, in the accent.
class _BackLink extends StatelessWidget {
  const _BackLink(this.parent);

  final SettingsPage parent;

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    final t = Tokens.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Tappable(
        label: 'Back to ${parent.label}',
        onTap: () => shell.showSettingsPage(parent),
        radius: BorderRadius.circular(8),
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              AppIcon('back', size: IconSize.xs, color: t.accent),
              Text(parent.label, style: Type.sans(13.5, color: t.accent)),
            ],
          ),
        ),
      ),
    );
  }
}
