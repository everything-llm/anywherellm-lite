import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../app_scope.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/tappable.dart';

/// The active workspace's chat mode, Agent, Chat or Query, which every message in it answers in,
/// as a list of what answers draw on. Changing it changes the workspace on the server, as its
/// settings in the web UI do. It waits while an answer runs in the workspace.
class ChatModeChooser extends StatelessWidget {
  const ChatModeChooser({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sources = scope.sources;
    final chat = scope.chat;
    return ListenableBuilder(
      listenable: Listenable.merge([sources.chatMode, chat]),
      builder: (context, _) {
        final mode = sources.chatMode.value;
        final slug = chat.activeSlug;
        final busy = slug == null || chat.answeringIn(slug);
        final enabled = !busy && mode != null;
        return Semantics(
          label: 'Chat mode',
          container: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 2,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: SectionLabel('Answer from'),
              ),
              for (final m in ChatMode.values)
                _Choice(
                  m,
                  chosen: m == mode,
                  onTap: enabled ? () => sources.setChatMode(m) : null,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One mode: a radio, what it answers from and the line under that, and the server's name for it.
class _Choice extends StatelessWidget {
  const _Choice(this.mode, {required this.chosen, required this.onTap});

  final ChatMode mode;
  final bool chosen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: chosen,
      child: Tappable(
        label: mode.label,
        selected: chosen,
        onTap: onTap,
        radius: BorderRadius.circular(10),
        color: chosen ? t.sel : null,
        dimWhenDisabled: 0.55,
        excludeSemantics: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [
              Container(
                width: 16,
                height: 16,
                margin: const EdgeInsets.only(top: 2),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: chosen ? t.accent : t.fade,
                    width: 1.5,
                  ),
                ),
                child: chosen
                    ? Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: t.accent,
                          shape: BoxShape.circle,
                        ),
                      )
                    : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 1,
                  children: [
                    Text(
                      mode.title,
                      style: Type.sans(
                        13.5,
                        weight: chosen ? FontWeight.w600 : FontWeight.w500,
                        color: t.ink,
                      ),
                    ),
                    Text(
                      mode.detail,
                      style: Type.sans(12.5, color: t.muted, height: 1.4),
                    ),
                  ],
                ),
              ),
              ExcludeSemantics(
                child: Text(
                  mode.label,
                  style: Type.sans(11.5, color: t.muted, height: 1.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
