import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'adapters/anythingllm_client.dart';
import 'adapters/browser_prefs_store_stub.dart'
    if (dart.library.js_interop) 'adapters/browser_prefs_store.dart';
import 'adapters/json_prefs_store.dart';
import 'adapters/keyring_settings_store.dart';
import 'core/connection.dart';
import 'core/ports.dart';
import 'ui/app.dart';
import 'ui/app_scope.dart';
import 'ui/boot_screen.dart';
import 'ui/chat/app_web_view.dart';
import 'ui/chat/device_speaker.dart';
import 'ui/chat/dictation.dart';
import 'ui/chat/speaker.dart';
import 'ui/chat/speech_dictation.dart';
import 'ui/files/save_android.dart';
import 'ui/files/save_file.dart';
import 'ui/files/share_file.dart';
import 'ui/settings/scan_code.dart';
import 'ui/share/android_shares.dart';
import 'ui/share/shared_item.dart';
import 'ui/settings/settings_pages.dart';
import 'ui/shell.dart';
import 'ui/state/chat_controller.dart';
import 'ui/state/files_controller.dart';
import 'ui/state/prefs_controller.dart';
import 'ui/state/settings_controller.dart';
import 'ui/state/shell_controller.dart';
import 'ui/state/sources_controller.dart';
import 'ui/state/system_controller.dart';

/// The composition root: the one place that knows the adapters and the UI.
///
/// The app talks only to the AnythingLLM server set up in Settings. The address and key live in
/// the system keyring; the other preferences in a JSON file. Android uses https only and keeps
/// the file in the app's private storage. In a browser both live in the page's local storage, and
/// a page served over https uses https only, since the browser blocks http from it.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final allowHttp = !_android && !(kIsWeb && Uri.base.scheme == 'https');
  final prefsFile = _android
      ? File('${(await getApplicationSupportDirectory()).path}/prefs.json')
      : null;
  final holder = ConnectionHolder();
  final llm = HttpAnythingLlmApi(
    holder: holder,
    allowHttp: allowHttp,
    browserOrigin: kIsWeb ? Uri.base.origin : null,
  );
  final prefs = PrefsController(
    kIsWeb ? BrowserPrefsStore() : JsonPrefsStore(prefsFile),
  );
  runApp(
    AnywhereLlmApp(
      prefs: prefs,
      home: SessionHost(
        llm: llm,
        settings: SettingsController(
          llm,
          KeyringSettingsStore(failureHint: _keyringHint),
          holder,
          allowHttp: allowHttp,
        ),
        prefs: prefs,
        shell: ShellController(),
        launch: (url) => launchUrl(url, mode: _launchMode(url)),
      ),
    ),
  );
}

/// Whether the app runs on Android. `Platform` throws in a browser, so it is asked only outside one.
final _android = !kIsWeb && Platform.isAndroid;
final _linux = !kIsWeb && Platform.isLinux;

/// Saves a file: a download in a browser, the system's save dialog elsewhere.
final FileSaver _save = kIsWeb
    ? saveAsDownload
    : _android
    ? saveWithPicker
    : saveWithDialog;

/// What to check when the keyring fails, after a space, or empty.
final _keyringHint = kIsWeb
    ? ' A browser keeps it only for a page served over https or from localhost.'
    : Platform.isLinux
    ? ' Is a secret service such as gnome-keyring running and unlocked?'
    : '';

/// How [url] opens: a web page in the in-app browser on Android, which Back closes, and
/// anything else, or anything on Linux, in the app the system picks, which in a browser is a
/// new tab. The in-app browser takes only http and https.
LaunchMode _launchMode(Uri url) =>
    _android && (url.scheme == 'http' || url.scheme == 'https')
    ? LaunchMode.inAppBrowserView
    : LaunchMode.externalApplication;

/// Reads the saved connection and preferences, then shows the app, with Settings open when no
/// server is set up.
class SessionHost extends StatefulWidget {
  const SessionHost({
    super.key,
    required this.llm,
    required this.settings,
    required this.prefs,
    required this.shell,
    required this.launch,
  });

  final AnythingLlmApi llm;
  final SettingsController settings;
  final PrefsController prefs;
  final ShellController shell;
  final LinkOpener launch;

  @override
  State<SessionHost> createState() => _SessionHostState();
}

class _SessionHostState extends State<SessionHost> {
  late Future<void> _loaded;
  late final ChatController _chat;
  late final SourcesController _sources;
  late final FilesController _files;
  late final SystemController _system;

  /// Reads answers aloud on Android, and is null where the device has no such engine to use.
  ReadAloud? _readAloud;

  /// Listens for speech on Android, and is null where the device has no such service to use.
  final Dictation? _dictation = _android ? SpeechDictation() : null;

  /// What other apps share with AnywhereLLM on Android, read once for the app's life.
  final Stream<SharedItem>? _shares = _android
      ? androidShares().asBroadcastStream()
      : null;

  /// The controllers listen before the keyring is read, so reading a saved connection is what
  /// loads the workspaces.
  @override
  void initState() {
    super.initState();
    // A browser opens only six connections to one server over HTTP/1.1, and each answer
    // holds one.
    _chat = ChatController(
      widget.llm,
      widget.settings,
      widget.prefs,
      maxRuns: kIsWeb ? 3 : null,
    );
    _sources = SourcesController(widget.llm, _chat, widget.prefs);
    _files = FilesController(
      widget.llm,
      widget.settings,
      _chat,
      widget.prefs,
      _sources,
    );
    _system = SystemController(widget.llm, widget.settings);
    if (_android) {
      _readAloud = ReadAloud(DeviceSpeaker(), _chat, widget.prefs);
    }
    // A deleted chat waiting to be undone is deleted before the app may be closed: Android can
    // end a hidden app without a word.
    _lifecycle = AppLifecycleListener(
      onHide: () => unawaited(_chat.flushDelete()),
      onExitRequested: () async {
        await _chat.flushDelete();
        return AppExitResponse.exit;
      },
    );
    _loaded = _load();
  }

  late final AppLifecycleListener _lifecycle;

  @override
  void dispose() {
    _lifecycle.dispose();
    _readAloud?.dispose();
    _system.dispose();
    _files.dispose();
    _sources.dispose();
    _chat.dispose();
    super.dispose();
  }

  /// Reads the prefs before the connection, so the workspace order and the last chat are known
  /// when the workspaces load.
  Future<void> _load() async {
    await widget.prefs.load();
    await widget.settings.load();
    if (!widget.settings.configured) {
      widget.shell.openSettings(SettingsPage.connection);
    }
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
        system: _system,
        launch: widget.launch,
        save: _save,
        scanner: _android ? cameraScanner : null,
        share: _android ? shareBytes : null,
        shares: _shares,
        appView: _android ? appWebView : null,
        dictation: _dictation,
        pasteImage: _linux ? () => Pasteboard.image : null,
        readAloud: _readAloud,
        labelAnswers: kIsWeb,
        canSpellcheck: WidgetsBinding
            .instance
            .platformDispatcher
            .nativeSpellCheckServiceDefined,
        child: const AppShell(),
      );
    },
  );
}
