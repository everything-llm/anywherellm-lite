import 'dart:async';

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../state/settings_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/phone_page.dart';
import 'chats_page.dart';
import 'connection_page.dart';
import 'device_pages.dart';
import 'embeds_page.dart';
import 'json_page.dart';
import 'memory_page.dart';
import 'privacy_page.dart';
import 'provider_page.dart';
import 'rows.dart';
import 'server_page.dart';
import 'settings_pages.dart';

/// Settings, a page over the window: a back arrow and the title, then the list in two groups,
/// This app and AnythingLLM, whose Server row opens the Server page, which lists the server's
/// pages.
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
          color: t.bg,
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

/// The list, or a page, under a back arrow and the title.
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
    final back = switch (page) {
      null => 'Back to the chat',
      final page => 'Back to ${page.parent?.label ?? 'Settings'}',
    };
    // A first run opens on its welcome alone, with no bar over it; Back still closes it.
    if (page == SettingsPage.connection && !configured) {
      return const _PageView(SettingsPage.connection);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhonePageHeader(
          title: page?.label ?? 'Settings',
          back: back,
          onBack: shell.settingsBack,
        ),
        Expanded(child: page == null ? const _Nav() : _PageView(page)),
      ],
    );
  }
}

/// The list of Settings: once a server is saved, a card with it, whether it answers and Test
/// connection; This app's pages; then AnythingLLM's Server and Memory rows.
class _Nav extends StatelessWidget {
  const _Nav();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final settings = scope.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.system, settings]),
      builder: (context, _) {
        final connection = settings.connection;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (connection != null) ...[
              const _ServerCard(),
              const SizedBox(height: 20),
            ],
            const CardHeading('This app'),
            const SizedBox(height: 8),
            FieldCard([
              for (final (page, icon) in const [
                (SettingsPage.connection, 'link'),
                (SettingsPage.appearance, 'settings'),
                (SettingsPage.chat, 'chat'),
              ])
                NavRow(
                  icon: icon,
                  title: page.label,
                  onTap: () => shell.showSettingsPage(page),
                ),
            ]),
            if (connection != null) ...[
              const SizedBox(height: 20),
              const CardHeading('AnythingLLM'),
              const SizedBox(height: 8),
              FieldCard([
                NavRow(
                  icon: 'activity',
                  title: SettingsPage.server.label,
                  about: serverSummary(scope.system),
                  onTap: () => shell.showSettingsPage(SettingsPage.server),
                ),
                NavRow(
                  icon: 'memory',
                  title: SettingsPage.memory.label,
                  about: 'Saved memories',
                  onTap: () => shell.showSettingsPage(SettingsPage.memory),
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
    final (state, color) = switch (settings.check) {
      ConnectionCheck.testing => ('Testing…', t.muted),
      ConnectionCheck.failed => ('Not answering', t.badfg),
      _ when scope.chat.unreachable.value => ('Connection problem', t.badfg),
      _ => ('Connected', t.okfg),
    };
    return FieldCard([
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FieldCard.inset,
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 2,
          children: [
            Row(
              spacing: 12,
              children: [
                Expanded(
                  child: Text(
                    'AnythingLLM',
                    style: Type.sans(19, weight: FontWeight.w500, color: t.ink),
                  ),
                ),
                Semantics(
                  liveRegion: true,
                  child: Text(state, style: Type.sans(13, color: color)),
                ),
              ],
            ),
            Text(
              connection.host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.mono(13, color: t.muted),
            ),
            if (settings.check == ConnectionCheck.failed)
              if (settings.message case final message?)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    message,
                    style: Type.sans(13, color: t.badfg, height: 1.4),
                  ),
                ),
          ],
        ),
      ),
      CardRow(
        'Test connection',
        tone: RowTone.accent,
        height: 56,
        onTap: settings.check == ConnectionCheck.testing
            ? null
            : () => unawaited(settings.testSaved()),
      ),
    ]);
  }
}

/// [page]'s line about what it is for, and its settings, scrolling. A new server builds it
/// afresh.
class _PageView extends StatelessWidget {
  const _PageView(this.page);

  final SettingsPage page;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final server = scope.settings.connection?.withPassword(null);
    final firstRun = page == SettingsPage.connection && server == null;
    return SingleChildScrollView(
      key: ValueKey(page),
      padding: firstRun
          ? const EdgeInsets.fromLTRB(24, 72, 24, 24)
          : const EdgeInsets.fromLTRB(20, 14, 20, 32),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The first run says what to do in its own words, and Appearance and Chat need no
              // line, as the design canvas draws them.
              if (firstRun || page == SettingsPage.chat)
                const SizedBox.shrink()
              else if (page == SettingsPage.appearance)
                const SizedBox(height: 2)
              else ...[
                Text(switch (page) {
                  SettingsPage.connection =>
                    'How this phone reaches AnythingLLM.',
                  SettingsPage.server => 'What AnythingLLM runs with. Each row opens the page that changes it.',
                  _ => page.about,
                }, style: Type.sans(14.5, color: t.ink2, height: 1.5)),
                const SizedBox(height: 14),
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
    SettingsPage.memory => const MemoryPage(),
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
