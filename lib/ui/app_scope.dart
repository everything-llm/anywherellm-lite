import 'package:flutter/widgets.dart';

import '../core/ports.dart';
import 'state/nav_controller.dart';
import 'state/settings_controller.dart';
import 'state/shell_controller.dart';
import 'state/upload_controller.dart';

/// The app's services, put in the tree once by `main.dart`. Controllers are listenable, so this
/// never notifies: widgets listen to the controller they read.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.llm,
    required this.nav,
    required this.shell,
    required this.upload,
    required this.settings,
    required super.child,
  });

  final AnythingLlmApi llm;
  final NavController nav;
  final ShellController shell;
  final UploadController upload;
  final SettingsController settings;

  static AppScope of(BuildContext context) {
    // Never notifies, so no dependency is needed. That also lets initState read it.
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'no AppScope above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => false;
}
