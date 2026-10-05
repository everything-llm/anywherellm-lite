import 'package:flutter/widgets.dart';

import 'state/chat_controller.dart';
import 'state/files_controller.dart';
import 'state/prefs_controller.dart';
import 'state/settings_controller.dart';
import 'state/shell_controller.dart';
import 'state/sources_controller.dart';

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
    required super.child,
  });

  final ShellController shell;
  final SettingsController settings;
  final PrefsController prefs;
  final ChatController chat;
  final SourcesController sources;
  final FilesController files;

  static AppScope of(BuildContext context) {
    // Never notifies, so no dependency is needed. That also lets initState read it.
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'no AppScope above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
