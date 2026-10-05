import 'package:everything/core/connection.dart';
import 'package:everything/ui/state/chat_controller.dart';
import 'package:everything/ui/state/prefs_controller.dart';
import 'package:everything/ui/state/settings_controller.dart';
import 'package:everything/ui/state/sources_controller.dart';

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
  }

  final FakeAnythingLlm llm;
  final FakeSettingsStore store;
  final FakePrefsStore prefsStore;
  late final SettingsController settings;
  late final PrefsController prefs;
  late final ChatController chat;
  late final SourcesController sources;

  /// Reads the prefs and the workspaces, as the app does at start.
  Future<void> start() async {
    await prefs.load();
    await chat.load();
    await sources.refresh();
  }

  void dispose() {
    sources.dispose();
    chat.dispose();
    settings.dispose();
    prefs.dispose();
  }
}
