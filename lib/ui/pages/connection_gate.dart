import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../state/nav_controller.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import 'page_frame.dart';

/// [child] once a server is set up, built afresh whenever the connection changes so it reads
/// the new server. Before that, a page that points to Settings.
class ConnectionGate extends StatelessWidget {
  const ConnectionGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final connection = settings.connection;
        if (connection != null) {
          return KeyedSubtree(key: ValueKey(connection), child: child);
        }
        return PageFrame(
          children: [
            const PageHead('No server yet'),
            const EmptyState(
              'Add your AnythingLLM server',
              'Enter its address and an API key in Settings. Then your workspaces and documents '
                  'show here.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: NilsButton(
                'Open Settings',
                primary: true,
                onPressed: () => scope.nav.go(const SettingsRoute()),
              ),
            ),
          ],
        );
      },
    );
  }
}
