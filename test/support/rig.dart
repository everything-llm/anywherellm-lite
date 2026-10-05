import 'package:everything/ui/state/inbox_controller.dart';
import 'package:everything/ui/state/overview_controller.dart';
import 'package:everything/ui/state/settings_controller.dart';

import 'fake_api.dart';
import 'fake_settings.dart';

/// A [FakeApi] with the overview, inbox and settings controllers over it.
class Rig {
  Rig(this.api, {FakeAnythingLlm? llm, FakeSettingsStore? store})
    : llm = llm ?? FakeAnythingLlm(),
      store = store ?? FakeSettingsStore() {
    overview = OverviewController(api, api.overviewValue);
    inbox = InboxController(api, overview);
    settings = SettingsController(this.llm, this.store);
  }

  final FakeApi api;
  final FakeAnythingLlm llm;
  final FakeSettingsStore store;
  late final OverviewController overview;
  late final InboxController inbox;
  late final SettingsController settings;

  void dispose() {
    settings.dispose();
    inbox.dispose();
    overview.dispose();
  }
}
