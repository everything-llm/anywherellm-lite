import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/ui/state/apps_controller.dart';
import 'package:anywherellm/ui/state/chat_controller.dart';
import 'package:anywherellm/ui/state/files_controller.dart';
import 'package:anywherellm/ui/state/prefs_controller.dart';
import 'package:anywherellm/ui/state/settings_controller.dart';
import 'package:anywherellm/ui/state/sources_controller.dart';
import 'package:anywherellm/ui/state/system_controller.dart';
import 'package:anywherellm/ui/state/toolkit_controller.dart';

import 'fake_api.dart';
import 'fake_apps.dart';
import 'fake_settings.dart';
import 'fake_toolkit.dart';

/// A [FakeAnythingLlm] with the app's controllers over it. [connection] is in use from the
/// start, as if read from the keyring.
class Rig {
  Rig({
    FakeAnythingLlm? llm,
    FakeSettingsStore? store,
    FakePrefsStore? prefsStore,
    FakeApps? appsServer,
    FakeToolkit? toolkitServer,
    Connection? connection,
  }) : llm = llm ?? FakeAnythingLlm(),
       appsServer = appsServer ?? FakeApps(),
       toolkitServer = toolkitServer ?? FakeToolkit(),
       store = store ?? FakeSettingsStore(),
       prefsStore = prefsStore ?? FakePrefsStore() {
    settings = SettingsController(
      this.llm,
      this.store,
      ConnectionHolder(connection),
    );
    prefs = PrefsController(this.prefsStore);
    chat = ChatController(this.llm, settings, prefs);
    sources = SourcesController(this.llm, chat, prefs);
    files = FilesController(this.llm, settings, chat, sources);
    system = SystemController(this.llm, settings);
    apps = AppsController(this.appsServer, settings, chat);
    toolkit = ToolkitController(this.toolkitServer, settings);
  }

  final FakeAnythingLlm llm;

  /// The apps server beside the fake AnythingLLM, absent unless a test makes it present.
  final FakeApps appsServer;

  /// The toolkit beside the fake AnythingLLM, present unless a test makes it absent.
  final FakeToolkit toolkitServer;
  final FakeSettingsStore store;
  final FakePrefsStore prefsStore;
  late final SettingsController settings;
  late final PrefsController prefs;
  late final ChatController chat;
  late final SourcesController sources;
  late final FilesController files;
  late final SystemController system;
  late final AppsController apps;
  late final ToolkitController toolkit;

  /// Reads the prefs and the workspaces, as the app does at start.
  Future<void> start() async {
    await prefs.load();
    await chat.load();
    await sources.refresh();
  }

  void dispose() {
    apps.dispose();
    toolkit.dispose();
    system.dispose();
    files.dispose();
    sources.dispose();
    chat.dispose();
    settings.dispose();
    prefs.dispose();
  }
}
