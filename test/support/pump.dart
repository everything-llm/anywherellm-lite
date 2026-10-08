import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/ui/app.dart';
import 'package:anywherellm/ui/app_scope.dart';
import 'package:anywherellm/ui/chat/composer.dart';
import 'package:anywherellm/ui/chat/dictation.dart';
import 'package:anywherellm/ui/chat/speaker.dart';
import 'package:anywherellm/ui/shell.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';
import 'fake_settings.dart';
import 'rig.dart';

/// A [Dictation] a test drives: [say] is what the microphone hears, and [finish] is the
/// recogniser ending the go, by a pause unless told otherwise. With [available] false it cannot listen.
class FakeDictation implements Dictation {
  bool available = true;
  int stopped = 0;
  void Function(String)? _onWords;
  void Function(DictationEnd how)? _onDone;

  bool get listening => _onWords != null;

  @override
  Future<bool> start({
    required void Function(String words) onWords,
    required void Function(DictationEnd how) onDone,
  }) async {
    if (!available) return false;
    _onWords = onWords;
    _onDone = onDone;
    return true;
  }

  @override
  Future<void> stop() async {
    stopped++;
    finish(DictationEnd.stopped);
  }

  void say(String words) => _onWords?.call(words);

  /// Ends the go as [how] says, a pause unless told otherwise.
  void finish([DictationEnd how = DictationEnd.paused]) {
    final done = _onDone;
    _onWords = null;
    _onDone = null;
    done?.call(how);
  }
}

/// A [Speaker] a test drives: it records what it was asked to read, and a reading lasts until
/// [finish] or [stop]. With [fails] set, reading throws it.
class FakeSpeaker implements Speaker {
  final List<String> spoken = [];
  int stopped = 0;
  Exception? fails;
  Completer<void>? _reading;

  @override
  Future<void> speak(String text) async {
    await stop();
    if (fails case final error?) throw error;
    spoken.add(text);
    final reading = _reading = Completer<void>();
    return reading.future;
  }

  @override
  Future<void> stop() async {
    stopped++;
    finish();
  }

  /// Ends the reading as the engine does when it reaches the end.
  void finish() {
    final reading = _reading;
    _reading = null;
    if (reading != null && !reading.isCompleted) reading.complete();
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
    bool canSpeak = false,
    this.labelAnswers = false,
    this.canSpellcheck = false,
    this.canPasteImages = false,
  }) : dictation = canDictate ? FakeDictation() : null,
       speaker = canSpeak ? FakeSpeaker() : null,
       shell = ShellController(sourcesPinned: sourcesOpen);

  final ShellController shell;

  /// Whether a finished answer carries its words as a semantics label, as in a browser.
  final bool labelAnswers;

  /// Whether the message box may spellcheck, as on Android.
  final bool canSpellcheck;

  /// Whether Ctrl+V reads a picture off the clipboard, as on Linux. It reads [clipboardImage].
  final bool canPasteImages;

  /// The picture on the fake clipboard, or null when it holds none.
  Uint8List? clipboardImage;

  /// What the microphone does, or null when the device cannot listen.
  final FakeDictation? dictation;

  /// What reads answers aloud, or null when the device cannot speak.
  final FakeSpeaker? speaker;

  late final ReadAloud? readAloud = switch (speaker) {
    final speaker? => ReadAloud(speaker, chat, prefs),
    null => null,
  };

  @override
  void dispose() {
    readAloud?.dispose();
    super.dispose();
  }

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
      system: system,
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
      pasteImage: canPasteImages ? () async => clipboardImage : null,
      readAloud: readAloud,
      labelAnswers: labelAnswers,
      canSpellcheck: canSpellcheck,
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
/// [connection], no server is set up. With [canScan], Settings offers a fake QR scanner, with
/// [canDictate] the composer a microphone, with [canSpeak] each answer Read aloud, and with
/// [labelAnswers] each finished answer a semantics label, as in a browser. With
/// [canPasteImages], Ctrl+V in the composer reads [Harness.clipboardImage].
Future<Harness> pumpApp(
  WidgetTester tester, {
  FakeAnythingLlm? llm,
  FakePrefsStore? prefsStore,
  Connection? connection = sampleConnection,
  Size size = const Size(1280, 800),
  bool sourcesOpen = true,
  bool canScan = false,
  bool canDictate = false,
  bool canSpeak = false,
  bool labelAnswers = false,
  bool canSpellcheck = false,
  bool canPasteImages = false,
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
    canSpeak: canSpeak,
    labelAnswers: labelAnswers,
    canSpellcheck: canSpellcheck,
    canPasteImages: canPasteImages,
  );
  addTearDown(harness.dispose);
  await harness.prefs.load();
  await tester.pumpWidget(harness.app);
  await harness.chat.load();
  // As the app's start does, once the connection is read.
  await harness.settings.readAuth();
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

/// The text field that has the focus, or else the composer.
Finder get typingInto {
  final focused = find.byWidgetPredicate(
    (widget) => widget is EditableText && widget.focusNode.hasFocus,
  );
  return focused.evaluate().isEmpty ? composerField : focused;
}

/// Types [text] where the focus is and presses Enter. Pumps a fixed time rather than settling,
/// since the caret of a streaming answer never stops blinking.
Future<void> typeAndEnter(WidgetTester tester, String text) async {
  await tester.enterText(typingInto, text);
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// The message in the composer.
String composerText(WidgetTester tester) =>
    tester.widget<EditableText>(composerField).controller.text;

/// Raises an on-screen keyboard [height] pixels tall as Android does: the window keeps its
/// size and reports the keyboard as a bottom view inset.
void raiseKeyboard(WidgetTester tester, double height) {
  tester.view.viewInsets = FakeViewPadding(bottom: height);
  addTearDown(tester.view.resetViewInsets);
}

/// Scrolls [finder] into view, then taps it, as a person scrolls to a control below the fold.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}
