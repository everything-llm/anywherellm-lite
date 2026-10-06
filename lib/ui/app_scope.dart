import 'package:flutter/widgets.dart';

import 'state/chat_controller.dart';
import 'state/files_controller.dart';
import 'state/prefs_controller.dart';
import 'state/settings_controller.dart';
import 'state/shell_controller.dart';
import 'state/sources_controller.dart';

/// Opens [url] outside the app, in the browser or the mail app. Says whether something did.
typedef LinkOpener = Future<bool> Function(Uri url);

/// Asks where to save a file called [suggestedName], then writes what [bytes] gives there.
/// Returns where it saved, or null when the person cancelled or [bytes] gave null. [bytes] runs
/// only after a place is chosen. Throws [Exception] when the device cannot ask or the file cannot
/// be written.
typedef FileSaver = Future<String?> Function(
  String suggestedName,
  Future<List<int>?> Function() bytes,
);

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
    required this.launch,
    required this.save,
    required super.child,
  });

  final ShellController shell;
  final SettingsController settings;
  final PrefsController prefs;
  final ChatController chat;
  final SourcesController sources;
  final FilesController files;
  final LinkOpener launch;
  final FileSaver save;

  static AppScope of(BuildContext context) {
    // Never notifies, so no dependency is needed. That also lets initState read it.
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'no AppScope above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
