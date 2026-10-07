import 'package:flutter/widgets.dart';

import 'chat/dictation.dart';
import 'chat/speaker.dart';
import 'state/chat_controller.dart';
import 'state/files_controller.dart';
import 'state/prefs_controller.dart';
import 'state/settings_controller.dart';
import 'state/shell_controller.dart';
import 'state/sources_controller.dart';
import 'state/system_controller.dart';

/// Opens [url] outside the app, in the browser or the mail app. Says whether something did.
typedef LinkOpener = Future<bool> Function(Uri url);

/// Asks where to save a file called [suggestedName], and writes what [bytes] gives there.
/// Returns where it saved, or null when the person cancelled or [bytes] gave null. On Linux
/// [bytes] runs only after a place is chosen; on Android it runs first, since the system's
/// dialog takes the bytes with it. A browser downloads the file and never asks. Throws [Exception] when the file cannot be written.
typedef FileSaver = Future<String?> Function(
  String suggestedName,
  Future<List<int>?> Function() bytes,
);

/// A camera view that reads QR codes and calls [onCode] with the first one's text.
typedef CodeScanner = Widget Function(void Function(String code) onCode);

/// The app's controllers, put in the tree once by `main.dart`. Controllers are listenable, so
/// this never notifies: widgets listen to the controller they read.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.shell,
    required this.settings,
    required this.prefs,
    required this.chat,
    required this.sources,
    required this.files,
    required this.system,
    required this.launch,
    required this.save,
    this.scanner,
    this.dictation,
    this.readAloud,
    this.labelAnswers = false,
    this.canSpellcheck = false,
    required super.child,
  });

  final ShellController shell;
  final SettingsController settings;
  final PrefsController prefs;
  final ChatController chat;
  final SourcesController sources;
  final FilesController files;
  final SystemController system;
  final LinkOpener launch;
  final FileSaver save;

  /// Reads a QR code in Settings, or null where the device has no camera to scan with.
  final CodeScanner? scanner;

  /// Writes what the person says in the composer, or null where the device cannot listen.
  final Dictation? dictation;

  /// Reads an answer aloud, or null where the device has no speech to read with.
  final ReadAloud? readAloud;

  /// Whether a finished answer carries its words as a semantics label, as in a browser, whose
  /// semantics tree leaves out selectable text; elsewhere the text is already there.
  final bool labelAnswers;

  /// Whether the platform has a spell checker the message box can use.
  final bool canSpellcheck;

  static AppScope of(BuildContext context) {
    // Never notifies, so no dependency is needed. That also lets initState read it.
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'no AppScope above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
