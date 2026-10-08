import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/ui/state/chat_controller.dart';
import 'package:anywherellm/ui/state/files_controller.dart';
import 'package:anywherellm/ui/state/prefs_controller.dart';
import 'package:anywherellm/ui/state/settings_controller.dart';
import 'package:anywherellm/ui/state/sources_controller.dart';
import 'package:anywherellm/ui/state/system_controller.dart';

import 'fake_api.dart';
import 'fake_settings.dart';

/// A [FakeAnythingLlm] with the app's controllers over it. [connection] is in use from the
/// start, as if read from the keyring. [maxRuns] caps the answers running at once, as in a
/// browser.
class Rig {
  Rig({
    FakeAnythingLlm? llm,
    FakeSettingsStore? store,
    FakePrefsStore? prefsStore,
    Connection? connection,
    int? maxRuns,
  }) : llm = llm ?? FakeAnythingLlm(),
       store = store ?? FakeSettingsStore(),
       prefsStore = prefsStore ?? FakePrefsStore() {
    settings = SettingsController(
      this.llm,
      this.store,
      ConnectionHolder(connection),
    );
    prefs = PrefsController(this.prefsStore);
    chat = ChatController(this.llm, settings, prefs, maxRuns: maxRuns);
    sources = SourcesController(this.llm, chat, prefs);
    files = FilesController(this.llm, settings, chat, prefs, sources);
    system = SystemController(this.llm, settings);
  }

  final FakeAnythingLlm llm;
  final FakeSettingsStore store;
  final FakePrefsStore prefsStore;
  late final SettingsController settings;
  late final PrefsController prefs;
  late final ChatController chat;
  late final SourcesController sources;
  late final FilesController files;
  late final SystemController system;

  /// Reads the prefs and the workspaces, as the app does at start.
  Future<void> start() async {
    await prefs.load();
    await chat.load();
    await sources.refresh();
  }

  void dispose() {
    system.dispose();
    files.dispose();
    sources.dispose();
    chat.dispose();
    settings.dispose();
    prefs.dispose();
  }
}
