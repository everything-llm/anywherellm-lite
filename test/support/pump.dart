import 'package:everything/core/connection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:everything/ui/app.dart';
import 'package:everything/ui/app_scope.dart';
import 'package:everything/ui/shell.dart';
import 'package:everything/ui/state/nav_controller.dart';
import 'package:everything/ui/state/shell_controller.dart';

import 'fake_api.dart';
import 'fake_settings.dart';
import 'rig.dart';

/// The controllers a test can read and drive, and the app built on them.
class Harness extends Rig {
  Harness({AppRoute? route, super.llm, super.store, super.connection})
    : nav = NavController(route),
      shell = ShellController();

  final NavController nav;
  final ShellController shell;

  Widget get app => NilsApp(
    home: AppScope(
      llm: llm,
      nav: nav,
      shell: shell,
      upload: upload,
      settings: settings,
      child: const AppShell(),
    ),
  );
}

/// Sizes the test window, builds the app on [llm] and lets the first loads finish. With no
/// [connection], no server is set up.
Future<Harness> pumpApp(
  WidgetTester tester, {
  FakeAnythingLlm? llm,
  FakeSettingsStore? store,
  Connection? connection,
  Size size = const Size(1200, 800),
  AppRoute? route,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = Harness(
    route: route,
    llm: llm,
    store: store,
    connection: connection,
  );
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  return harness;
}
