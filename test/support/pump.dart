import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/ui/app.dart';
import 'package:anywherellm/ui/app_scope.dart';
import 'package:anywherellm/ui/chat/composer.dart';
import 'package:file_selector/file_selector.dart' show XFile;
import 'package:anywherellm/ui/chat/dictation.dart';
import 'package:anywherellm/ui/chat/photo_picker.dart';
import 'package:anywherellm/ui/chat/speaker.dart';
import 'package:anywherellm/ui/share/shared_item.dart';
import 'package:anywherellm/ui/shell.dart';
import 'package:anywherellm/ui/state/browser_controller.dart';
import 'package:anywherellm/ui/state/created_controller.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';
import 'fake_settings.dart';
import 'rig.dart';

/// A [PhotoPicker] that gives [chosen] from the library and [taken] from the camera, or with
/// [cameraFails] a camera that cannot be used.
class FakePhotos implements PhotoPicker {
  List<XFile> chosen = [];
  XFile? taken;
  bool cameraFails = false;

  @override
  Future<List<XFile>> choose() async => chosen;

  @override
  Future<XFile?> take() async {
    if (cameraFails) throw StateError('camera_access_denied');
    return taken;
  }
}

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
    // Off, so no check is left waiting on the test's clock: its controllers outlive the tree.
    super.checkEvery = const [],
    bool sourcesOpen = true,
    this.canScan = false,
    bool canDictate = false,
    bool canPickPhotos = false,
    bool canSpeak = false,
    this.labelAnswers = false,
    this.canSpellcheck = false,
    this.canPasteImages = false,
    this.canShare = false,
    this.shares,
    this.canViewApps = false,
    this.canTakeOver = false,
    this.browserEvery,
  }) : dictation = canDictate ? FakeDictation() : null,
       photos = canPickPhotos ? FakePhotos() : null,
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

  /// The device's photos and camera, or null where there are none.
  final FakePhotos? photos;

  /// What the microphone does, or null when the device cannot listen.
  final FakeDictation? dictation;

  /// What reads answers aloud, or null when the device cannot speak.
  final FakeSpeaker? speaker;

  /// The chat on screen's browser as the fake server says it. It reads at the pace of
  /// [browserEvery], or never on a timer, which a test that opens the panel need not wait out.
  late final BrowserController browser = BrowserController(
    llm,
    chat,
    shell,
    every: browserEvery,
  );

  /// How often the open panel reads the browser, or null for never.
  final Duration? browserEvery;

  /// The open workspace's created files as the fake server lists them.
  late final CreatedController created = CreatedController(llm, settings, chat);

  late final ReadAloud? readAloud = switch (speaker) {
    final speaker? => ReadAloud(speaker, chat, prefs),
    null => null,
  };

  @override
  void dispose() {
    created.dispose();
    browser.dispose();
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

  /// Whether the device has a share sheet. Each file handed to it is kept in [shared].
  final bool canShare;

  /// What other apps share with the app, as a test adds it, or null where it receives none.
  final StreamController<SharedItem>? shares;

  /// Whether an app's sheet shows its page, as on Android. The page is a line of text naming it.
  final bool canViewApps;

  /// The web view an app's page shows in, with [canViewApps].
  final appPages = FakeAppView();

  /// Whether the chat's browser shows as the take-over view, as on Android.
  final bool canTakeOver;

  /// The web view the take-over view shows in, with [canTakeOver].
  final takeover = FakeTakeover();

  /// Every file the app shared, by name, with its bytes.
  final Map<String, List<int>> shared = {};

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
      browser: browser,
      created: created,
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
      share: canShare ? (name, bytes) async => shared[name] = bytes : null,
      shares: shares?.stream,
      appView: canViewApps ? appPages : null,
      takeover: canTakeOver ? takeover : null,
      dictation: dictation,
      photos: photos,
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
/// [canDictate] the composer a microphone, with [canPickPhotos] the Attach sheet the device's
/// photos and camera, with [canSpeak] each answer Read aloud, and with
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
  bool canPickPhotos = false,
  bool canSpeak = false,
  bool labelAnswers = false,
  bool canSpellcheck = false,
  bool canPasteImages = false,
  bool canShare = false,
  StreamController<SharedItem>? shares,
  bool canViewApps = false,
  bool canTakeOver = false,
  Duration? browserEvery,
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
    canShare: canShare,
    shares: shares,
    canViewApps: canViewApps,
    canTakeOver: canTakeOver,
    canDictate: canDictate,
    canPickPhotos: canPickPhotos,
    canSpeak: canSpeak,
    labelAnswers: labelAnswers,
    canSpellcheck: canSpellcheck,
    canPasteImages: canPasteImages,
    browserEvery: browserEvery,
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

/// The control a screen reader hears as [label].
Finder control(String label) => find.byWidgetPredicate(
  (widget) => widget is Tappable && widget.label == label,
);

/// Scrolls [finder] into view, then taps it, as a person scrolls to a control below the fold.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

/// The sidebar's workspace switcher.
Finder get switcher => find.byWidgetPredicate(
  (widget) =>
      widget is Tappable &&
      widget.label.startsWith('Workspaces') &&
      widget.tooltip == 'Switch workspace',
);

/// Opens the sidebar's workspace menu and picks [item] in it.
Future<void> fromMenu(WidgetTester tester, String item) async {
  await tester.tap(switcher);
  await tester.pumpAndSettle();
  await tester.tap(control(item).last);
  await tester.pumpAndSettle();
}

/// Opens the chat on screen's ⋯ in the sidebar and picks [item] in it.
Future<void> chatAction(WidgetTester tester, String item) async {
  await tester.tap(control('Chat actions: rename, pin, delete'));
  await tester.pumpAndSettle();
  await tester.tap(control(item).last);
  await tester.pumpAndSettle();
}

/// A web view that draws an app's page as the text `Web view of <page>` and records each page
/// prefetched, in order, without one asked again in a row.
class FakeAppView implements AppView {
  final prefetched = <Uri>[];

  @override
  void prefetch(Uri page) {
    if (prefetched.lastOrNull != page) prefetched.add(page);
  }

  @override
  Widget show(
    Uri page, {
    required Widget placeholder,
    required void Function(Uri url) onLeave,
  }) => Text('Web view of $page');
}

/// A web view that draws the take-over view as the text `Take-over view of <page>`, with the
/// page's Back as a button heard as Page back. [say] sends a message as the page's message bar
/// does.
class FakeTakeover implements TakeoverView {
  Future<String> Function(String text)? _say;

  /// Sends [text] as the page's message bar does, and answers the line the app gives back.
  Future<String> say(String text) => _say!(text);

  @override
  Widget show(
    Uri page, {
    required Widget placeholder,
    required VoidCallback onBack,
    required Future<String> Function(String text) onSay,
    required void Function(Uri url) onLeave,
  }) {
    _say = onSay;
    return Column(
      children: [
        Text('Take-over view of $page'),
        Tappable(label: 'Page back', onTap: onBack, child: const Text('Back')),
      ],
    );
  }
}
