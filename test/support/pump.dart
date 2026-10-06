import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/ui/app.dart';
import 'package:anywherellm/ui/app_scope.dart';
import 'package:anywherellm/ui/chat/composer.dart';
import 'package:anywherellm/ui/chat/dictation.dart';
import 'package:anywherellm/ui/shell.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';
import 'fake_settings.dart';
import 'rig.dart';

/// A [Dictation] a test drives: [say] is what the microphone hears, and [finish] is the
/// recogniser ending the go. With [available] false it cannot listen.
class FakeDictation implements Dictation {
  bool available = true;
  int stopped = 0;
  void Function(String)? _onWords;
  void Function()? _onDone;

  bool get listening => _onWords != null;

  @override
  Future<bool> start({
    required void Function(String words) onWords,
    required void Function() onDone,
  }) async {
    if (!available) return false;
    _onWords = onWords;
    _onDone = onDone;
    return true;
  }

  @override
  Future<void> stop() async {
    stopped++;
    finish();
  }

  void say(String words) => _onWords?.call(words);

  void finish() {
    final done = _onDone;
    _onWords = null;
    _onDone = null;
    done?.call();
  }
}

/// The controllers a test can read and drive, and the app built on them.
class Harness extends Rig {
  Harness({
    super.llm,
    super.store,
    super.prefsStore,
    super.connection,
    bool sourcesOpen = true,
    this.canScan = false,
    bool canDictate = false,
  }) : dictation = canDictate ? FakeDictation() : null,
       shell = ShellController(sourcesPinned: sourcesOpen);

  final ShellController shell;

  /// What the microphone does, or null when the device cannot listen.
  final FakeDictation? dictation;

  /// Every address the app asked to open, in order.
  final List<Uri> opened = [];

  /// Whether opening a link succeeds, as when the device has a browser.
  bool openSucceeds = true;

  /// What opening a link throws, when set.
  Object? openThrows;

  /// Whether the device can scan a QR code. Its scanner is a Fake scan button that reads
  /// [scanCode].
  final bool canScan;

  /// The text the fake scanner reads.
  String scanCode = '';

  /// Every file the app saved, by the name it suggested, with its bytes.
  final Map<String, List<int>> saved = {};

  /// Whether the person picks a place in the save dialog rather than cancelling.
  bool saveChosen = true;

  /// What saving a file throws, when set.
  Exception? saveThrows;

  Widget get app => AnywhereLlmApp(
    prefs: prefs,
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
      dictation: dictation,
      scanner: canScan
          ? (onCode) => TextButton(
              onPressed: () => onCode(scanCode),
              child: const Text('Fake scan'),
            )
          : null,
      child: const AppShell(),
    ),
  );
}

/// Sizes the test window, builds the app on [llm] and lets the first loads finish. With no
/// [connection], no server is set up. With [canScan], Settings offers a fake QR scanner, and with [canDictate] the composer a
/// microphone.
Future<Harness> pumpApp(
  WidgetTester tester, {
  FakeAnythingLlm? llm,
  FakePrefsStore? prefsStore,
  Connection? connection = sampleConnection,
  Size size = const Size(1280, 800),
  bool sourcesOpen = true,
  bool canScan = false,
  bool canDictate = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = Harness(
    llm: llm,
    prefsStore: prefsStore,
    connection: connection,
    sourcesOpen: sourcesOpen,
    canScan: canScan,
    canDictate: canDictate,
  );
  addTearDown(harness.dispose);
  await harness.prefs.load();
  await tester.pumpWidget(harness.app);
  await harness.chat.load();
  await tester.pumpAndSettle();
  return harness;
}

/// The fields a person types in, under [of] when given: an answer is a read-only one.
Finder typingField([Finder? of]) {
  final field = find.byWidgetPredicate((w) => w is EditableText && !w.readOnly);
  return of == null ? field : find.descendant(of: of, matching: field);
}

/// The composer's field, apart from the sidebar's search and every other field on screen.
Finder get composerField => typingField(find.byType(Composer));

/// Raises an on-screen keyboard [height] pixels tall as Android does: the window keeps its
/// size and reports the keyboard as a bottom view inset.
void raiseKeyboard(WidgetTester tester, double height) {
  tester.view.viewInsets = FakeViewPadding(bottom: height);
  addTearDown(tester.view.resetViewInsets);
}
