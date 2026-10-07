import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// The way to Settings at the foot of the sidebar, with whether a key is set.
class SidebarSettingsButton extends StatelessWidget {
  const SidebarSettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: scope.settings,
      builder: (context, _) {
        final set = scope.settings.configured;
        return Tappable(
          label: 'Settings',
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
                    color: set ? t.okdot : t.warnfg,
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
                        set ? 'Connected to AnythingLLM' : 'Not connected',
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
