import 'package:everything/core/connection.dart';
import 'package:everything/ui/state/settings_controller.dart';
import 'package:everything/ui/state/upload_controller.dart';

import 'fake_api.dart';
import 'fake_settings.dart';

/// A [FakeAnythingLlm] with the settings and upload controllers over it. [connection] is in use
/// from the start, as if read from the keyring.
class Rig {
  Rig({FakeAnythingLlm? llm, FakeSettingsStore? store, Connection? connection})
    : llm = llm ?? FakeAnythingLlm(),
      store = store ?? FakeSettingsStore() {
    final holder = ConnectionHolder(connection);
    settings = SettingsController(this.llm, this.store, holder);
    upload = UploadController(this.llm, holder);
  }

  final FakeAnythingLlm llm;
  final FakeSettingsStore store;
  late final SettingsController settings;
  late final UploadController upload;

  void dispose() {
    settings.dispose();
    upload.dispose();
  }
}
