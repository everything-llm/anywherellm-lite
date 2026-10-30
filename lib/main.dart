import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'adapters/anythingllm_client.dart';
import 'adapters/json_prefs_store.dart';
import 'adapters/keyring_settings_store.dart';
import 'core/connection.dart';
import 'core/ports.dart';
import 'ui/app.dart';
import 'ui/app_scope.dart';
import 'ui/boot_screen.dart';
import 'ui/chat/android_background.dart';
import 'ui/chat/background_work.dart';
import 'ui/chat/device_speaker.dart';
import 'ui/chat/device_photos.dart';
import 'ui/chat/dictation.dart';
import 'ui/chat/photo_picker.dart';
import 'ui/chat/speaker.dart';
import 'ui/chat/speech_dictation.dart';
import 'ui/files/save_android.dart';
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
/// The app talks only to the AnythingLLM server set up in Settings, over https. The address and
/// key live in the Android Keystore; the other preferences in a JSON file in the app's private
/// storage.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefsFile = File(
    '${(await getApplicationSupportDirectory()).path}/prefs.json',
  );
  final holder = ConnectionHolder();
  final llm = HttpAnythingLlmApi(holder: holder);
  final prefs = PrefsController(JsonPrefsStore(prefsFile));
  runApp(
    AnywhereLlmApp(
      prefs: prefs,
      home: SessionHost(
        llm: llm,
        settings: SettingsController(llm, KeyringSettingsStore(), holder),
        prefs: prefs,
        shell: ShellController(),
        launch: (url) => launchUrl(url, mode: _launchMode(url)),
      ),
    ),
  );
}

/// How [url] opens: a web page in the in-app browser, which Back closes, and anything else, as
/// a `mailto:` link, in the app the system picks. The in-app browser takes only http and https.
LaunchMode _launchMode(Uri url) => url.scheme == 'http' || url.scheme == 'https'
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

  /// Keeps an answer going while the app is out of sight.
  final BackgroundWork _background = AndroidBackground();
  late final KeepAnswering _keepAnswering;

  /// Reads answers aloud with the device's engine.
  late final ReadAloud _readAloud;

  /// Listens for speech with the device's recognition service.
  final Dictation _dictation = SpeechDictation();

  /// The device's photos and camera, for the composer's Attach sheet.
  final PhotoPicker _photos = DevicePhotos();

  /// What other apps share with AnywhereLLM, read once for the app's life.
  final Stream<SharedItem> _shares = androidShares().asBroadcastStream();

  /// The controllers listen before the keyring is read, so reading a saved connection is what
  /// loads the workspaces.
  @override
  void initState() {
    super.initState();
    _chat = ChatController(widget.llm, widget.settings, widget.prefs);
    _sources = SourcesController(widget.llm, _chat, widget.prefs);
    _files = FilesController(widget.llm, widget.settings, _chat, _sources);
    _system = SystemController(widget.llm, widget.settings);
    _readAloud = ReadAloud(DeviceSpeaker(), _chat, widget.prefs);
    _keepAnswering = KeepAnswering(_background, _chat, widget.shell);
    // A deleted chat waiting to be undone goes as the app hides: Android can end a hidden app
    // without a word.
    _lifecycle = AppLifecycleListener(
      onHide: () => unawaited(_chat.flushDelete()),
    );
    _loaded = _load();
  }

  late final AppLifecycleListener _lifecycle;

  @override
  void dispose() {
    _lifecycle.dispose();
    _readAloud.dispose();
    _keepAnswering.dispose();
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
        save: saveWithPicker,
        scanner: cameraScanner,
        share: shareBytes,
        shares: _shares,
        dictation: _dictation,
        photos: _photos,
        readAloud: _readAloud,
        background: _background,
        canSpellcheck: WidgetsBinding
            .instance
            .platformDispatcher
            .nativeSpellCheckServiceDefined,
        enterSends: switch (defaultTargetPlatform) {
          TargetPlatform.linux ||
          TargetPlatform.macOS ||
          TargetPlatform.windows => true,
          TargetPlatform.android ||
          TargetPlatform.iOS ||
          TargetPlatform.fuchsia => false,
        },
        child: const AppShell(),
      );
    },
  );
}
