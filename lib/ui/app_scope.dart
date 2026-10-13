import 'package:flutter/widgets.dart';

import 'apps/app_screen.dart';
import 'chat/dictation.dart';
import 'chat/photo_picker.dart';
import 'chat/speaker.dart';
import 'share/shared_item.dart';
import 'state/apps_controller.dart';
import 'state/chat_controller.dart';
import 'state/files_controller.dart';
import 'state/memory_controller.dart';
import 'state/prefs_controller.dart';
import 'state/push_controller.dart';
import 'state/settings_controller.dart';
import 'state/shell_controller.dart';
import 'state/sources_controller.dart';
import 'state/system_controller.dart';

/// Opens [url] outside the app, in the browser or the mail app. Says whether something did.
typedef LinkOpener = Future<bool> Function(Uri url);

/// Asks where to save a file called [suggestedName], and writes what [bytes] gives there.
/// Returns where it saved, or null when the person cancelled or [bytes] gave null. [bytes] runs
/// first, since the system's dialog takes the bytes with it. Throws [Exception] when the file
/// cannot be written.
typedef FileSaver = Future<String?> Function(
  String suggestedName,
  Future<List<int>?> Function() bytes,
);

/// Hands the file [name], holding [bytes], to the system's share sheet.
typedef FileSharer = Future<void> Function(String name, List<int> bytes);

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
    required this.memory,
    required this.apps,
    required this.launch,
    required this.save,
    this.scanner,
    this.share,
    this.shares,
    this.dictation,
    this.photos,
    this.readAloud,
    this.appView,
    this.push,
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

  /// The Memory page's saved memories.
  final MemoryController memory;

  /// The apps server beside the server in use, when it is there, and its apps.
  final AppsController apps;
  final LinkOpener launch;
  final FileSaver save;

  /// Reads a QR code in Settings, or null where the device has no camera to scan with.
  final CodeScanner? scanner;

  /// Shares a file an agent made with another app, or null where the device has no share
  /// sheet.
  final FileSharer? share;

  /// What other apps share with AnywhereLLM, or null where the device has no share sheet to
  /// receive from.
  final Stream<SharedItem>? shares;

  /// Writes what the person says in the composer, or null where the device cannot listen.
  final Dictation? dictation;

  /// Pictures from the device's photos and camera for the composer's Attach sheet, or null
  /// where the device has neither, and Attach opens the file picker.
  final PhotoPicker? photos;

  /// Reads an answer aloud, or null where the device has no speech to read with.
  final ReadAloud? readAloud;

  /// Shows an app's working page in a web view, or null where the device has none, and an app
  /// shows its card with a way to its page in the browser.
  final AppView? appView;

  /// Push notifications, or null where the device cannot receive them.
  final PushController? push;

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
