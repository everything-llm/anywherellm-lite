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
  Harness(super.api, {AppRoute? route, super.llm, super.store})
    : nav = NavController(route),
      shell = ShellController();

  final NavController nav;
  final ShellController shell;

  Widget get app => NilsApp(
    home: AppScope(
      api: api,
      nav: nav,
      shell: shell,
      overview: overview,
      inbox: inbox,
      settings: settings,
      child: const AppShell(),
    ),
  );
}

/// Sizes the test window, builds the app on [api] and lets the first loads finish.
Future<Harness> pumpApp(
  WidgetTester tester, {
  FakeApi? api,
  FakeAnythingLlm? llm,
  FakeSettingsStore? store,
  Size size = const Size(1200, 800),
  AppRoute? route,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = Harness(
    api ?? FakeApi(),
    route: route,
    llm: llm,
    store: store,
  );
  await tester.pumpWidget(harness.app);
  await tester.pumpAndSettle();
  return harness;
}
