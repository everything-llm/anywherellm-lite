// The app as `tool/audit/audit.py` runs it on an emulator: the real window, adapters for the
// device and screens, over the test fakes holding the design prototype's sample data, so no
// server is reached and nothing real shows. It is built with
//
//   flutter build apk --debug -t tool/audit_app.dart
//
// and `--dart-define=AUDIT_SIGNED_OUT=true` starts it with no server saved. The fakes are in
// memory, so each launch starts from the same state. It sits outside `lib/`, so the shipping app
// never holds the fakes.

import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/main.dart' show SessionHost;
import 'package:anywherellm/ui/app.dart';
import 'package:anywherellm/ui/state/prefs_controller.dart';
import 'package:anywherellm/ui/state/settings_controller.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/material.dart';

import '../test/support/fake_settings.dart';
import 'sample.dart';

const _signedOut = bool.fromEnvironment('AUDIT_SIGNED_OUT');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final (llm, toolkit) = sampleServer();
  final prefs = PrefsController(FakePrefsStore());
  runApp(
    AnywhereLlmApp(
      prefs: prefs,
      home: SessionHost(
        llm: llm,
        toolkit: toolkit,
        settings: SettingsController(
          llm,
          FakeSettingsStore(_signedOut ? null : sampleServerConnection),
          ConnectionHolder(),
        ),
        prefs: prefs,
        shell: ShellController(),
        launch: (url) async => true,
      ),
    ),
  );
}
