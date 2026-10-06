import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/ui/state/chat_controller.dart';
import 'package:anywherellm/ui/state/files_controller.dart';
import 'package:anywherellm/ui/state/prefs_controller.dart';
import 'package:anywherellm/ui/state/settings_controller.dart';
import 'package:anywherellm/ui/state/sources_controller.dart';

import 'fake_api.dart';
import 'fake_settings.dart';

/// A [FakeAnythingLlm] with the app's controllers over it. [connection] is in use from the
/// start, as if read from the keyring.
class Rig {
  Rig({
    FakeAnythingLlm? llm,
    FakeSettingsStore? store,
    FakePrefsStore? prefsStore,
    Connection? connection,
  }) : llm = llm ?? FakeAnythingLlm(),
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
    files = FilesController(this.llm, settings, chat, prefs, sources);
  }

  final FakeAnythingLlm llm;
  final FakeSettingsStore store;
  final FakePrefsStore prefsStore;
  late final SettingsController settings;
  late final PrefsController prefs;
  late final ChatController chat;
  late final SourcesController sources;
  late final FilesController files;

  /// Reads the prefs and the workspaces, as the app does at start.
  Future<void> start() async {
    await prefs.load();
    await chat.load();
    await sources.refresh();
  }

  void dispose() {
    files.dispose();
    sources.dispose();
    chat.dispose();
    settings.dispose();
    prefs.dispose();
  }
}
