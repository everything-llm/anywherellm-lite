import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../app_scope.dart';
import '../widgets/fields.dart';
import '../widgets/segmented.dart';

/// The active workspace's chat mode, Agent, Chat or Query, which every message in it answers in.
/// Changing it changes the workspace on the server, as its settings in the web UI do. It waits
/// while an answer runs in the workspace.
class ChatModeChooser extends StatelessWidget {
  const ChatModeChooser({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sources = scope.sources;
    final chat = scope.chat;
    return ListenableBuilder(
      listenable: Listenable.merge([sources, chat]),
      builder: (context, _) {
        final mode = sources.chatMode.value;
        final slug = chat.activeSlug;
        final busy = slug == null || chat.answeringIn(slug);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: 'Chat mode',
              container: true,
              child: Segmented(
                options: [for (final m in ChatMode.values) (m, m.label)],
                value: mode,
                onChanged: busy || mode == null ? null : sources.setChatMode,
              ),
            ),
            if (mode != null) ...[
              const SizedBox(height: 6),
              HelpText(mode.about, status: true),
            ],
          ],
        );
      },
    );
  }
}
