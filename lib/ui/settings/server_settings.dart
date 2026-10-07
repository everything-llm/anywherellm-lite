import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../widgets/basics.dart';
import '../widgets/confirm_box.dart';
import '../widgets/fields.dart';

/// A page over the server's settings: they are read when it shows unless they are already, and
/// [builder] draws them as the server has them, with [revision] counting each fresh read. Why a
/// read or save failed shows above them.
class ServerSettings extends StatefulWidget {
  const ServerSettings({
    super.key,
    required this.builder,
    this.before = const [],
    this.after = const [],
  });

  final Widget Function(Map<String, Object?> values, int revision) builder;
  final List<Widget> before;
  final List<Widget> after;

  @override
  State<ServerSettings> createState() => _ServerSettingsState();
}

class _ServerSettingsState extends State<ServerSettings> {
  @override
  void initState() {
    super.initState();
    AppScope.of(context).system.wantSettings();
  }

  @override
  Widget build(BuildContext context) {
    final system = AppScope.of(context).system;
    return ListenableBuilder(
      listenable: system,
      builder: (context, _) {
        final values = system.settings;
        final problem = system.settingsProblem;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 20,
          children: [
            ...widget.before,
            if (problem != null)
              AlertBox(AlertKind.bad, problem.title, text: problem.text),
            if (values != null)
              widget.builder(values, system.settingsRevision)
            else if (problem == null)
              const HelpText('Reading the server\'s settings…', status: true),
            ...widget.after,
          ],
        );
      },
    );
  }
}

/// Saves a draft of the server's settings, asking first when it changes one that deletes every
/// vector.
mixin SettingsSaving<T extends StatefulWidget> on State<T> {
  /// The settings whose change waits for the person to confirm it, while asking.
  List<String>? confirming;

  Future<void> save(String draft) async {
    final system = AppScope.of(context).system;
    final resets = system.vectorResets(draft);
    if (resets.isNotEmpty && confirming == null) {
      setState(() => confirming = resets);
      return;
    }
    setState(() => confirming = null);
    await system.saveSettings(draft);
  }

  /// The question asked before such a change, or nothing.
  Widget? confirmBox(String Function() draft) {
    final resets = confirming;
    if (resets == null) return null;
    final count = AppScope.of(context).system.vectors;
    final passages = count == null ? 'every passage' : 'all $count passages';
    return ConfirmBox(
      text:
          'Changing ${resets.join(' and ')} makes the server delete $passages it has stored. '
          'Every workspace\'s documents must then be prepared again before answers can use them.',
      action: 'Change and delete',
      onCancel: () => setState(() => confirming = null),
      onConfirm: () => save(draft()),
    );
  }
}
