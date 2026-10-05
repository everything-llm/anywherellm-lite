import 'dart:io';

import 'package:flutter/material.dart';

import 'adapters/anythingllm_client.dart';
import 'adapters/cli_nils_api.dart';
import 'adapters/keyring_settings_store.dart';
import 'adapters/nils_command.dart';
import 'core/models.dart';
import 'core/ports.dart';
import 'ui/app.dart';
import 'ui/app_scope.dart';
import 'ui/boot_screen.dart';
import 'ui/shell.dart';
import 'ui/state/inbox_controller.dart';
import 'ui/state/nav_controller.dart';
import 'ui/state/overview_controller.dart';
import 'ui/state/settings_controller.dart';
import 'ui/state/shell_controller.dart';

/// The composition root: the one place that knows the adapters and the UI.
///
/// The app reads and files through the `nils` command in a checkout of the nils repository. Set
/// `NILS_REPO` to that checkout; without it the app looks above the working directory and the
/// executable for one, or for a sibling directory named `nils`.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsController(
    HttpAnythingLlmApi(),
    KeyringSettingsStore(),
  )..load();
  runApp(
    NilsApp(
      home: SessionHost(
        settings: settings,
        open: () async => _connected(_command()),
      ),
    ),
  );
}

/// The environment variable [name], or null when it is unset or empty.
String? _env(String name) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? null : value;
}

/// The command for the nils checkout, or the reason there is none.
NilsCommand _command() {
  final given = _env('NILS_REPO');
  final repo = given != null
      ? Directory(given)
      : NilsCommand.findRepo([
          Directory.current,
          File(Platform.resolvedExecutable).parent,
        ]);
  if (repo == null ||
      !Directory('${repo.path}/storage/data/research').existsSync()) {
    throw ApiException(
      given == null
          ? 'no nils checkout found; set NILS_REPO to the directory holding storage/data/research'
          : 'NILS_REPO is $given, which holds no storage/data/research',
    );
  }
  return NilsCommand.forRepo(repo);
}

/// The API over [command] and the overview it answered with, once it has answered one request.
///
/// A checkout that cannot be read is reported here as a start-up failure and not as a page full
/// of loads that each fail.
Future<(NilsApi, Overview)> _connected(NilsCommand command) async {
  final api = CliNilsApi(command);
  return (api, await api.overview());
}

/// Opens the API, then shows the app on it, or why it could not be opened.
class SessionHost extends StatefulWidget {
  const SessionHost({super.key, required this.settings, required this.open});

  final SettingsController settings;
  final Future<(NilsApi, Overview)> Function() open;

  @override
  State<SessionHost> createState() => _SessionHostState();
}

class _Session {
  _Session(this.api, Overview first)
    : nav = NavController(),
      shell = ShellController(),
      overview = OverviewController(api, first) {
    inbox = InboxController(api, overview);
  }

  final NilsApi api;
  final NavController nav;
  final ShellController shell;
  final OverviewController overview;
  late final InboxController inbox;
}

class _SessionHostState extends State<SessionHost> {
  late Future<_Session> _session;

  @override
  void initState() {
    super.initState();
    _session = _boot();
  }

  Future<_Session> _boot() async {
    final (api, overview) = await widget.open();
    return _Session(api, overview);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_Session>(
    future: _session,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return BootError(
          message: '${snapshot.error}',
          onRetry: () => setState(() => _session = _boot()),
        );
      }
      final session = snapshot.data;
      if (session == null) return const BootScreen();
      return AppScope(
        api: session.api,
        nav: session.nav,
        shell: session.shell,
        overview: session.overview,
        inbox: session.inbox,
        settings: widget.settings,
        child: const AppShell(),
      );
    },
  );
}
