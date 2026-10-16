import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../widgets/basics.dart';
import '../widgets/fields.dart';

/// A page over the server's settings: they are read when it shows unless they are already, and
/// [builder] draws them as the server has them. Why a read or save failed shows above them.
class ServerSettings extends StatefulWidget {
  const ServerSettings({super.key, required this.builder});

  final Widget Function(Map<String, Object?> values) builder;

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
            if (problem != null) AlertBox.notice(AlertKind.bad, problem),
            if (values != null)
              widget.builder(values)
            else if (problem == null)
              const HelpText('Reading the server\'s settings…', status: true),
          ],
        );
      },
    );
  }
}
