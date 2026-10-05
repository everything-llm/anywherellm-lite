import 'package:flutter/material.dart';

import 'adapters/anythingllm_client.dart';
import 'adapters/json_prefs_store.dart';
import 'adapters/keyring_settings_store.dart';
import 'core/connection.dart';
import 'core/ports.dart';
import 'ui/app.dart';
import 'ui/app_scope.dart';
import 'ui/boot_screen.dart';
import 'ui/shell.dart';
import 'ui/state/chat_controller.dart';
import 'ui/state/files_controller.dart';
import 'ui/state/prefs_controller.dart';
import 'ui/state/settings_controller.dart';
import 'ui/state/shell_controller.dart';
import 'ui/state/sources_controller.dart';

/// The composition root: the one place that knows the adapters and the UI.
///
/// The app talks only to the AnythingLLM server set up in Settings. The address and key live in
/// the system keyring; the other preferences in a JSON file.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final holder = ConnectionHolder();
  final llm = HttpAnythingLlmApi(holder: holder);
  runApp(
    NilsApp(
      home: SessionHost(
        llm: llm,
        settings: SettingsController(llm, KeyringSettingsStore(), holder),
        prefs: PrefsController(JsonPrefsStore()),
        shell: ShellController(),
      ),
    ),
  );
}

/// Reads the saved connection and preferences, then shows the app, with Settings open when no
/// server is set up.
class SessionHost extends StatefulWidget {
  const SessionHost({
    super.key,
    required this.llm,
    required this.settings,
    required this.prefs,
    required this.shell,
  });

  final AnythingLlmApi llm;
  final SettingsController settings;
  final PrefsController prefs;
  final ShellController shell;

  @override
  State<SessionHost> createState() => _SessionHostState();
}

class _SessionHostState extends State<SessionHost> {
  late Future<void> _loaded;
  late final ChatController _chat;
  late final SourcesController _sources;
  late final FilesController _files;

  /// The controllers listen before the keyring is read, so reading a saved connection is what
  /// loads the workspaces.
  @override
  void initState() {
    super.initState();
    _chat = ChatController(widget.llm, widget.settings, widget.prefs);
    _sources = SourcesController(widget.llm, _chat, widget.prefs);
    _files = FilesController(
      widget.llm,
      widget.settings,
      _chat,
      widget.prefs,
      _sources,
    );
    _loaded = _load();
  }

  @override
  void dispose() {
    _files.dispose();
    _sources.dispose();
    _chat.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Future.wait([widget.settings.load(), widget.prefs.load()]);
    if (!widget.settings.configured) widget.shell.openSettings();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _loaded,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return BootError(
          message: '${snapshot.error}',
          onRetry: () => setState(() => _loaded = _load()),
        );
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const BootScreen();
      }
      return AppScope(
        shell: widget.shell,
        settings: widget.settings,
        prefs: widget.prefs,
        chat: _chat,
        sources: _sources,
        files: _files,
        child: const AppShell(),
      );
    },
  );
}
