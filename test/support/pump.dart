import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/ui/app.dart';
import 'package:anywherellm/ui/app_scope.dart';
import 'package:anywherellm/ui/shell.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';
import 'fake_settings.dart';
import 'rig.dart';

/// The controllers a test can read and drive, and the app built on them.
class Harness extends Rig {
  Harness({
    super.llm,
    super.store,
    super.prefsStore,
    super.connection,
    bool sourcesOpen = true,
  }) : shell = ShellController(sourcesPinned: sourcesOpen);

  final ShellController shell;

  /// Every address the app asked to open, in order.
  final List<Uri> opened = [];

  /// Whether opening a link succeeds, as when the device has a browser.
  bool openSucceeds = true;

  /// What opening a link throws, when set.
  Object? openThrows;

  /// Every file the app saved, by the name it suggested, with its bytes.
  final Map<String, List<int>> saved = {};

  /// Whether the person picks a place in the save dialog rather than cancelling.
  bool saveChosen = true;

  /// What saving a file throws, when set.
  Exception? saveThrows;

  Widget get app => AnywhereLlmApp(
    home: AppScope(
      shell: shell,
      settings: settings,
      prefs: prefs,
      chat: chat,
      sources: sources,
      files: files,
      launch: (url) async {
        opened.add(url);
        if (openThrows case final error?) throw error;
        return openSucceeds;
      },
      save: (name, bytes) async {
        if (saveThrows case final error?) throw error;
        if (!saveChosen) return null;
        final data = await bytes();
        if (data == null) return null;
        saved[name] = data;
        return '/saved/$name';
      },
      child: const AppShell(),
    ),
  );
}

/// Sizes the test window, builds the app on [llm] and lets the first loads finish. With no
/// [connection], no server is set up.
Future<Harness> pumpApp(
  WidgetTester tester, {
  FakeAnythingLlm? llm,
  FakePrefsStore? prefsStore,
  Connection? connection = sampleConnection,
  Size size = const Size(1280, 800),
  bool sourcesOpen = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = Harness(
    llm: llm,
    prefsStore: prefsStore,
    connection: connection,
    sourcesOpen: sourcesOpen,
  );
  addTearDown(harness.dispose);
  await harness.prefs.load();
  await tester.pumpWidget(harness.app);
  await harness.chat.load();
  await tester.pumpAndSettle();
  return harness;
}
