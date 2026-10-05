import 'package:everything/ui/state/inbox_controller.dart';
import 'package:everything/ui/state/overview_controller.dart';

import 'fake_api.dart';

/// A [FakeApi] with the overview and inbox controllers over it.
class Rig {
  Rig(this.api) {
    overview = OverviewController(api, api.overviewValue);
    inbox = InboxController(api, overview);
  }

  final FakeApi api;
  late final OverviewController overview;
  late final InboxController inbox;

  void dispose() {
    inbox.dispose();
    overview.dispose();
  }
}
