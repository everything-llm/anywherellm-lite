import 'package:anywherellm/core/connection.dart';
import 'package:anywherellm/ui/app.dart';
import 'package:anywherellm/ui/app_scope.dart';
import 'package:anywherellm/ui/apps/app_screen.dart';
import 'package:anywherellm/ui/chat/background_work.dart';
import 'package:anywherellm/ui/chat/composer.dart';
import 'package:cross_file/cross_file.dart';
import 'package:anywherellm/ui/chat/dictation.dart';
import 'package:anywherellm/ui/chat/photo_picker.dart';
import 'package:anywherellm/ui/chat/speaker.dart';
import 'package:anywherellm/ui/share/shared_item.dart';
import 'package:anywherellm/ui/shell.dart';
import 'package:anywherellm/ui/state/memory_controller.dart';
import 'package:anywherellm/ui/state/push_controller.dart';
import 'package:anywherellm/ui/state/shell_controller.dart';
import 'package:anywherellm/ui/widgets/tappable.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_api.dart';
import 'fake_apps.dart';
import 'fake_toolkit.dart';
import 'fake_background.dart';
import 'fake_pusher.dart';
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

/// An [AppView] that draws an app's page as the text `Web view of <page>`.
class FakeAppView implements AppView {
  final List<Uri> shown = [];

  /// How the page shown last closes itself, as its `window.close()` does.
  VoidCallback? close;

  /// The channel the page shown last was given, whose scripts run are kept in [ran].
  PageChannel? channel;
  final List<String> ran = [];

  @override
  Widget show(
    Uri page, {
    required void Function(Uri url) onLeave,
    VoidCallback? onClose,
    PageChannel? channel,
  }) {
    shown.add(page);
    close = onClose;
    this.channel = channel?..runner = (script) async => ran.add(script);
    return Center(child: Text('Web view of $page'));
  }
}

/// The controllers a test can read and drive, and the app built on them.
class Harness extends Rig {
  Harness({
    super.llm,
    super.store,
    super.prefsStore,
    super.appsServer,
    super.toolkitServer,
    super.connection,
    bool canViewApps = false,
    this.canScan = false,
    bool canDictate = false,
    bool canPickPhotos = false,
    bool canSpeak = false,
    this.canSpellcheck = false,
    this.canShare = false,
    this.shares,
    this.pusher,
    this.background,
  }) : dictation = canDictate ? FakeDictation() : null,
       photos = canPickPhotos ? FakePhotos() : null,
       speaker = canSpeak ? FakeSpeaker() : null,
       appView = canViewApps ? FakeAppView() : null,
       shell = ShellController();

  final ShellController shell;

  /// The device's web view for an app's page, or null where there is none.
  final FakeAppView? appView;

  /// Whether the message box may spellcheck, as on Android.
  final bool canSpellcheck;

  /// The device's photos and camera, or null where there are none.
  final FakePhotos? photos;

  /// What the microphone does, or null when the device cannot listen.
  final FakeDictation? dictation;

  /// What reads answers aloud, or null when the device cannot speak.
  final FakeSpeaker? speaker;

  /// The Memory page's memories as the fake server keeps them.
  late final MemoryController memory = MemoryController(
    toolkitServer,
    settings,
    chat,
  );

  /// The device's push distributor, or null where it receives none.
  final FakePusher? pusher;

  /// What keeps answers going out of sight, or null where nothing does.
  final FakeBackground? background;

  late final KeepAnswering? keepAnswering = switch (background) {
    final background? => KeepAnswering(background, chat),
    null => null,
  };

  late final PushController? push = switch (pusher) {
    final pusher? => PushController(
      pusher,
      appsServer,
      settings,
      chat,
      apps,
      shell,
    ),
    null => null,
  };

  late final ReadAloud? readAloud = switch (speaker) {
    final speaker? => ReadAloud(speaker, chat, prefs),
    null => null,
  };

  @override
  void dispose() {
    memory.dispose();
    push?.dispose();
    keepAnswering?.dispose();
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
      memory: memory,
      apps: apps,
      toolkit: toolkit,
      appView: appView,
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
      dictation: dictation,
      photos: photos,
      readAloud: readAloud,
      push: push,
      background: background,
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

/// A phone's window, upright.
const phoneSize = Size(390, 844);

/// Sizes the test window, builds the app on [llm] and lets the first loads finish. With no
/// [connection], no server is set up. With [canScan], Settings offers a fake QR scanner, with
/// [canDictate] the composer a microphone, with [canPickPhotos] the Attach sheet the device's
/// photos and camera, and with [canSpeak] each answer Read aloud. [appsServer] is the apps
/// server beside it, absent unless given present, [toolkitServer] the toolkit, present unless
/// given absent, and [canViewApps] draws an app's page with a
/// [FakeAppView]. The window is a phone's,
/// [phoneSize], unless [size] says otherwise. The chat shows full screen, as after a chat is
/// tapped on the Chats tab, unless [onChat] is false, which leaves the home showing.
Future<Harness> pumpApp(
  WidgetTester tester, {
  FakeAnythingLlm? llm,
  FakePrefsStore? prefsStore,
  FakeApps? appsServer,
  FakeToolkit? toolkitServer,
  bool canViewApps = false,
  Connection? connection = sampleConnection,
  Size size = phoneSize,
  bool canScan = false,
  bool canDictate = false,
  bool canPickPhotos = false,
  bool canSpeak = false,
  bool canSpellcheck = false,
  bool canShare = false,
  StreamController<SharedItem>? shares,
  FakePusher? pusher,
  FakeBackground? background,
  bool onChat = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = Harness(
    llm: llm,
    prefsStore: prefsStore,
    appsServer: appsServer,
    toolkitServer: toolkitServer,
    canViewApps: canViewApps,
    connection: connection,
    canScan: canScan,
    canShare: canShare,
    shares: shares,
    pusher: pusher,
    background: background,
    canDictate: canDictate,
    canPickPhotos: canPickPhotos,
    canSpeak: canSpeak,
    canSpellcheck: canSpellcheck,
  );
  addTearDown(harness.dispose);
  await harness.prefs.load();
  if (onChat) harness.shell.openChat();
  await tester.pumpWidget(harness.app);
  await harness.chat.load();
  await harness.push?.load();
  // Built now, as the app builds it at start, so it holds from the first answer.
  harness.keepAnswering;
  await tester.pumpAndSettle();
  return harness;
}

/// The fields a person types in, under [of] when given: an answer is a read-only one.
Finder typingField([Finder? of]) {
  final field = find.byWidgetPredicate((w) => w is EditableText && !w.readOnly);
  return of == null ? field : find.descendant(of: of, matching: field);
}

/// The composer's field, apart from the drawer's search and every other field on screen.
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
