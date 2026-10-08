import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// The way to Settings at the foot of the sidebar, with whether a server is set and answers: the
/// server's host while it does, with its whole address as the tooltip.
class SidebarSettingsButton extends StatelessWidget {
  const SidebarSettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.settings, scope.chat.unreachable]),
      builder: (context, _) {
        final set = scope.settings.configured;
        final ok = set && !scope.chat.unreachable.value;
        final server = scope.settings.connection;
        final state = switch (server) {
          final server? when ok => 'Connected to ${server.host}',
          _ when set => 'Connection problem',
          _ => 'Not connected',
        };
        return Tappable(
          label: 'Settings, $state',
          tooltip: ok ? server?.baseUrl : null,
          onTap: scope.shell.openSettings,
          radius: BorderRadius.circular(Sizes.control),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: ok ? t.okdot : t.warnfg,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Settings',
                        style: Type.sans(
                          13.5,
                          weight: FontWeight.w500,
                          color: t.ink,
                        ),
                      ),
                      Text(
                        state,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.sans(12, color: t.muted),
                      ),
                    ],
                  ),
                ),
                AppIcon('settings', size: IconSize.sm, color: t.muted),
              ],
            ),
          ),
        );
      },
    );
  }
}
