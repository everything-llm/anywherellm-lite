import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../layout.dart';
import '../list_detail.dart';
import '../state/settings_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/list_row.dart';
import '../widgets/phone_page.dart';
import '../widgets/sheet.dart';
import '../widgets/window_insets.dart';
import 'connection_page.dart';
import 'device_pages.dart';
import 'privacy_page.dart';
import 'shortcuts_page.dart';
import 'rows.dart';
import 'server_page.dart';
import 'settings_pages.dart';
import '../widgets/scroll_fades.dart';

/// Settings: its list over the chat, opened from the shelf's foot, in two groups, This app and
/// AnythingLLM, whose Server row opens the Server page; a page shows over what showed. Each is
/// under a back arrow and its name. On a wide window the list and the page show side by side.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

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
    final t = Tokens.of(context);
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Settings',
      child: FocusScope(
        autofocus: true,
        child: ColoredBox(
          color: t.ground,
          child: ListenableBuilder(
            listenable: Listenable.merge([scope.shell, scope.settings]),
            builder: (context, _) => _Frame(
              page: scope.shell.settingsPage,
              configured: scope.settings.configured,
            ),
          ),
        ),
      ),
    );
  }
}

/// The list or a page, each under a back arrow and its name, or on a wide window both side by
/// side.
class _Frame extends StatelessWidget {
  const _Frame({required this.page, required this.configured});

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
    final split = Wide.split(context);
    if (split) return _SplitFrame(page ?? SettingsPage.connection);
    // A first run opens on its welcome alone, with no header over it; Back still closes it.
    if (page == SettingsPage.connection && !configured) {
      return const _PageView(SettingsPage.connection);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhonePageHeader(
          title: page?.label ?? 'Settings',
          back: page == null
              ? 'Back to the chat'
              : 'Back to ${page.parent?.label ?? 'Settings'}',
          onBack: shell.settingsBack,
        ),
        Expanded(
          child: ScrollFades(
            child: page == null ? const _Nav() : _PageView(page),
          ),
        ),
      ],
    );
  }
}

/// The list of Settings: once a server is saved, a card with it, whether it answers and Test
/// connection; This app's pages; then AnythingLLM's Server row.
///
/// Beside a page ([split]), its rows are drawn as a wide window's list, [chosen]'s marked.
class _Nav extends StatelessWidget {
  const _Nav({this.chosen, this.split = false});

  /// The row of the page shown beside the list.
  final SettingsPage? chosen;
  final bool split;

  /// A row that opens [page], with [icon] and the line [about] under its name.
  Widget _row(
    BuildContext context,
    SettingsPage page,
    String icon, {
    String? about,
  }) {
    final shell = AppScope.of(context).shell;
    void open() => shell.showSettingsPage(page);
    if (!split) {
      return NavRow(icon: icon, title: page.label, about: about, onTap: open);
    }
    return ListRow(
      icon: icon,
      title: page.label,
      about: about,
      selected: page == chosen,
      onTap: open,
    );
  }

  /// A group of [rows]: a grouped card, or beside a page a card of a wide window's rows.
  Widget _group(BuildContext context, List<Widget> rows) =>
      split ? ListCard(rows) : FieldCard(rows);

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.system, settings]),
      builder: (context, _) {
        final connection = settings.connection;
        return ListView(
          padding: split ? EdgeInsets.zero : Sizes.pageIn(context),
          children: [
            if (connection != null) const _ServerCard(),
            CardHeading('This app', top: connection != null ? 20 : 0),
            _group(context, [
              _row(context, SettingsPage.connection, 'link'),
              _row(context, SettingsPage.appearance, 'brush'),
              _row(context, SettingsPage.chat, 'chat'),
            ]),
            if (connection != null) ...[
              const CardHeading('AnythingLLM'),
              _group(context, [
                _row(
                  context,
                  SettingsPage.server,
                  'server',
                  about: serverSummary(scope.system),
                ),
              ]),
            ],
          ],
        );
      },
    );
  }
}

/// The server saved, on the list of Settings: whether it answers, its host, and Test connection.
class _ServerCard extends StatelessWidget {
  const _ServerCard();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.settings, scope.chat.unreachable]),
      builder: _build,
    );
  }

  Widget _build(BuildContext context, Widget? _) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    final t = Tokens.of(context);
    final connection = settings.connection!;
    // The word in ink beside its status's icon; Testing… is no status, so it stands alone.
    final (state, status) = switch (settings.check) {
      ConnectionCheck.testing => ('Testing…', null),
      ConnectionCheck.failed => ('Not answering', Status.danger),
      _ when scope.chat.unreachable.value => (
        'Connection problem',
        Status.danger,
      ),
      _ => ('Connected', Status.success),
    };
    return SummaryCard(
      title: 'AnythingLLM',
      trailing: Semantics(
        liveRegion: true,
        child: StatusWord(state, status: status),
      ),
      lines: [
        Text(
          connection.host,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Type.code(t.muted),
        ),
        if (settings.check == ConnectionCheck.failed)
          if (settings.message case final message?)
            Text(message, style: Type.note(t.danger)),
      ],
      action: AppButton(
        'Test connection',
        primary: true,
        onPressed: settings.check == ConnectionCheck.testing
            ? null
            : () => unawaited(settings.testSaved()),
      ),
    );
  }
}

/// [page]'s line about what it is for, and its settings, scrolling. A new server builds it
/// afresh.
class _PageView extends StatelessWidget {
  const _PageView(this.page, {this.split = false});

  final SettingsPage page;

  /// Whether the page shows beside the list, in a card of its own, as wide as a column.
  final bool split;

  // Const on a first run, so it listens itself to the settings for the server it keys on.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppScope.of(context).settings,
    builder: _build,
  );

  Widget _build(BuildContext context, Widget? _) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final server = scope.settings.connection;
    final firstRun = page == SettingsPage.connection && server == null;
    final column = Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: split ? Sizes.column : 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (page.about case final about?) ...[
              Text(about, style: Type.note(t.ink)),
              const SizedBox(height: 14),
            ],
            KeyedSubtree(key: ValueKey((page, server)), child: _body(page)),
          ],
        ),
      ),
    );
    // The first run lays out and scrolls itself, to keep Connect above the keyboard.
    if (firstRun) {
      return KeyedSubtree(key: ValueKey(page), child: _body(page));
    }
    return SingleChildScrollView(
      key: ValueKey(page),
      padding: split
          ? const EdgeInsets.fromLTRB(24, 8, 24, 24)
          : Sizes.pageIn(context),
      child: column,
    );
  }

  static Widget _body(SettingsPage page) => switch (page) {
    SettingsPage.connection => const ConnectionPage(),
    SettingsPage.server => const ServerPage(),
    SettingsPage.appearance => const AppearancePage(),
    SettingsPage.chat => const ChatPage(),
    SettingsPage.shortcuts => const ShortcutsPage(),
    SettingsPage.privacy => const PrivacyPage(),
  };
}

/// Settings on a wide window: its title over the list and [page] side by side, the list's row
/// of the page shown marked. Beside the sidebar there is no way back but the sidebar; with the
/// shelf, a back arrow gives back the chat.
class _SplitFrame extends StatelessWidget {
  const _SplitFrame(this.page);

  final SettingsPage page;

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(
          title: 'Settings',
          back: 'Back to the chat',
          onBack: shell.closeSettings,
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + WindowInsets.of(context).bottom,
            ),
            child: ListDetail(
              list: ScrollFades(
                child: _Nav(chosen: page.parent ?? page, split: true),
              ),
              detail: _Detail(page),
            ),
          ),
        ),
      ],
    );
  }
}

/// [page] beside the list, in a card under its name, with a back arrow to its parent when it has
/// one, as Privacy and data has the Server page.
class _Detail extends StatelessWidget {
  const _Detail(this.page);

  final SettingsPage page;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final parent = page.parent;
    final firstRun =
        page == SettingsPage.connection && scope.settings.connection == null;
    final body = _PageView(page, split: true);
    return DetailCard(
      title: page.label,
      back: 'Back to ${parent?.label}',
      onBack: parent == null
          ? null
          : () => scope.shell.showSettingsPage(parent),
      // The first run lays out and scrolls itself. Its cards are wells in this one.
      child: SheetCards(child: firstRun ? body : ScrollFades(child: body)),
    );
  }
}
