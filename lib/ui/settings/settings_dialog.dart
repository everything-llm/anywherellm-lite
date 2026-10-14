import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../layout.dart';
import '../state/settings_controller.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/phone_page.dart';
import '../widgets/sheet.dart';
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
import 'walkthrough.dart';

/// Settings: its list as the Settings tab, under its title, in two groups, This app and
/// AnythingLLM, whose Server row opens the Server page, which lists the server's pages; a page
/// shows over what showed under a back arrow and its name. The shell draws the bar of tabs
/// under both.
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

/// The list as a tab, or a page under a back arrow and its name.
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
    // A first run opens on its welcome alone, with no bar over it; Back still closes it.
    if (page == SettingsPage.connection && !configured) {
      return const _PageView(SettingsPage.connection);
    }
    if (page == null) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabTitle('Settings'),
          Expanded(child: _Nav()),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhonePageHeader(
          title: page.label,
          back: 'Back to ${page.parent?.label ?? 'Settings'}',
          onBack: shell.settingsBack,
        ),
        Expanded(child: _PageView(page)),
      ],
    );
  }
}

/// The list of Settings: once a server is saved, a card with it, whether it answers and Test
/// connection; This app's pages; then AnythingLLM's Server and Memory rows; and, while no
/// toolkit answers beside the server, a card that opens Add the toolkit over the list.
class _Nav extends StatelessWidget {
  const _Nav();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final settings = scope.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([scope.system, settings, scope.toolkit]),
      builder: (context, _) {
        final connection = settings.connection;
        final list = ListView(
          padding: Sizes.pagePadding,
          children: [
            if (connection != null) const _ServerCard(),
            CardHeading('This app', top: connection != null ? 20 : 0),
            FieldCard([
              for (final (page, icon) in [
                (SettingsPage.connection, 'link'),
                (SettingsPage.appearance, 'brush'),
                (SettingsPage.chat, 'chat'),
              ])
                NavRow(
                  icon: icon,
                  title: page.label,
                  onTap: () => shell.showSettingsPage(page),
                ),
            ]),
            if (connection != null) ...[
              const CardHeading('AnythingLLM'),
              FieldCard([
                NavRow(
                  icon: 'server',
                  title: SettingsPage.server.label,
                  about: serverSummary(scope.system),
                  onTap: () => shell.showSettingsPage(SettingsPage.server),
                ),
                if (scope.toolkit.memories)
                  NavRow(
                    icon: 'memory',
                    title: SettingsPage.memory.label,
                    onTap: () => shell.showSettingsPage(SettingsPage.memory),
                  ),
              ]),
              if (scope.toolkit.available == false) ...[
                const SizedBox(height: 20),
                SummaryCard(
                  title: 'Get more from your server',
                  lines: [
                    Text(
                      'Install the free toolkit beside AnythingLLM to add Memory here '
                      'and Upcoming on the Chats tab.',
                      style: Type.sans(13, color: Tokens.of(context).muted),
                    ),
                  ],
                  link: 'See how to add it',
                  onLink: () => shell.showGuide(Guide.toolkit),
                ),
              ],
            ],
          ],
        );
        return ListenableBuilder(
          listenable: shell,
          child: list,
          builder: (context, list) => OverlayWhile(
            open: shell.guide == Guide.toolkit,
            overlay: (context) => const _ToolkitGuide(),
            child: list!,
          ),
        );
      },
    );
  }
}

/// Add the toolkit, over the list of Settings. Its end opens the Connection page with the
/// camera reading, for the code the toolkit's installer shows, where there is a camera.
class _ToolkitGuide extends StatelessWidget {
  const _ToolkitGuide();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final canScan = scope.scanner != null;
    return Walkthrough(
      title: 'Add the toolkit',
      steps: toolkitSteps,
      onClose: () => shell.showGuide(null),
      end: canScan ? 'Scan the installer\'s code' : 'Close',
      endAbout: canScan
          ? 'or close and scan it later'
          : 'scan it on a phone with a camera',
      onEnd: () {
        shell.showGuide(null);
        if (!canScan) return;
        shell
          ..showSettingsPage(SettingsPage.connection)
          ..setScanning(true);
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
    return SummaryCard(
      title: 'AnythingLLM',
      trailing: Semantics(
        liveRegion: true,
        child: Text(state, style: Type.sans(15, color: color)),
      ),
      lines: [
        Text(
          connection.host,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Type.mono(13, color: t.muted, height: 1.45),
        ),
        if (settings.check == ConnectionCheck.failed)
          if (settings.message case final message?)
            Text(message, style: Type.sans(13, color: t.badfg, height: 1.4)),
      ],
      link: 'Test connection',
      onLink: settings.check == ConnectionCheck.testing
          ? null
          : () => unawaited(settings.testSaved()),
    );
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
    final server = scope.settings.connection;
    final firstRun = page == SettingsPage.connection && server == null;
    final column = Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (page.about case final about?) ...[
              Text(about, style: Type.sans(14.5, color: t.ink2, height: 1.5)),
              const SizedBox(height: 14),
            ],
            KeyedSubtree(key: ValueKey((page, server)), child: _body(page)),
          ],
        ),
      ),
    );
    if (!firstRun) {
      return SingleChildScrollView(
        key: ValueKey(page),
        padding: Sizes.pagePadding,
        child: column,
      );
    }
    // The first run is top-aligned and scrolls, so a short screen loses nothing. How connecting
    // works sits at the foot while there is room, and follows Connect where there is not.
    const top = 56.0, bottom = 8.0;
    return LayoutBuilder(
      key: ValueKey(page),
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, top, 16, bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, box.maxHeight - top - bottom),
          ),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                column,
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: GuideLink(
                    'How connecting works',
                    onTap: () => scope.shell.showGuide(Guide.connect),
                  ),
                ),
              ],
            ),
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
