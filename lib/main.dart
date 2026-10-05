import 'package:flutter/material.dart';

import 'adapters/anythingllm_client.dart';
import 'adapters/keyring_settings_store.dart';
import 'core/connection.dart';
import 'core/ports.dart';
import 'ui/app.dart';
import 'ui/app_scope.dart';
import 'ui/boot_screen.dart';
import 'ui/shell.dart';
import 'ui/state/nav_controller.dart';
import 'ui/state/settings_controller.dart';
import 'ui/state/shell_controller.dart';
import 'ui/state/upload_controller.dart';

/// The composition root: the one place that knows the adapters and the UI.
///
/// The app talks only to the AnythingLLM server set up in Settings. The address and key live in
/// the system keyring.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final holder = ConnectionHolder();
  final llm = HttpAnythingLlmApi(holder: holder);
  runApp(
    NilsApp(
      home: SessionHost(
        llm: llm,
        holder: holder,
        settings: SettingsController(llm, KeyringSettingsStore(), holder),
      ),
    ),
  );
}

/// Reads the saved connection, then shows the app: on the workspaces, or on Settings when no
/// server is set up.
class SessionHost extends StatefulWidget {
  const SessionHost({
    super.key,
    required this.llm,
    required this.holder,
    required this.settings,
  });

  final AnythingLlmApi llm;

  /// The connection in use, which [settings] keeps.
  final ConnectionHolder holder;
  final SettingsController settings;

  @override
  State<SessionHost> createState() => _SessionHostState();
}

class _SessionHostState extends State<SessionHost> {
  late Future<NavController> _loaded;
  final _shell = ShellController();
  late final _upload = UploadController(widget.llm, widget.holder);

  @override
  void initState() {
    super.initState();
    _loaded = _load();
  }

  Future<NavController> _load() async {
    await widget.settings.load();
    return NavController(
      widget.settings.configured ? null : const SettingsRoute(),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<NavController>(
    future: _loaded,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return BootError(
          message: '${snapshot.error}',
          onRetry: () => setState(() => _loaded = _load()),
        );
      }
      final nav = snapshot.data;
      if (nav == null) return const BootScreen();
      return AppScope(
        llm: widget.llm,
        nav: nav,
        shell: _shell,
        upload: _upload,
        settings: widget.settings,
        child: const AppShell(),
      );
    },
  );
}
