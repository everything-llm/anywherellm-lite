import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/tappable.dart';

/// Where a question is written. Enter sends it and Shift+Enter starts a new line. While this
/// chat answers, Send becomes Stop; while another chat answers, nothing can be sent.
class Composer extends StatelessWidget {
  const Composer({super.key, required this.draft, required this.focus});

  final TextEditingController draft;
  final FocusNode focus;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.column),
          child: ListenableBuilder(
            listenable: Listenable.merge([scope.settings, scope.chat, draft]),
            builder: (context, _) => scope.settings.configured
                ? _Form(draft: draft, focus: focus)
                : const _NoKey(),
          ),
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.draft, required this.focus});

  final TextEditingController draft;
  final FocusNode focus;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final t = Tokens.of(context);
    final here = chat.answeringHere;
    final elsewhere = chat.busy && !here;
    final hint = here
        ? 'Answering…'
        : elsewhere
        ? 'Another chat is still answering…'
        : 'Ask about your files…';
    final canSend =
        !chat.busy &&
        chat.ready &&
        chat.active != null &&
        draft.text.trim().isNotEmpty;

    void send() {
      if (!canSend) return;
      final text = draft.text;
      draft.clear();
      chat.send(text);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: BorderRadius.circular(Sizes.card),
        border: Border.all(color: t.line),
        boxShadow: [
          BoxShadow(
            color: t.shadow.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: t.shadow,
            blurRadius: 24,
            spreadRadius: -12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 26, maxHeight: 140),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): send,
                const SingleActivator(LogicalKeyboardKey.numpadEnter): send,
              },
              child: Semantics(
                label: 'Message',
                textField: true,
                child: TextField(
                  controller: draft,
                  focusNode: focus,
                  enabled: !chat.busy,
                  minLines: 1,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: Type.sans(15.5, color: t.ink, height: 1.5),
                  cursorColor: t.accent,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: hint,
                    hintStyle: Type.sans(15.5, color: t.fade, height: 1.5),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Tappable(
                label: 'AnythingLLM settings',
                onTap: scope.shell.openSettings,
                radius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Text(
                    'AnythingLLM',
                    style: Type.sans(13, color: t.muted),
                  ),
                ),
              ),
              const Spacer(),
              if (here)
                _RoundButton(
                  label: 'Stop',
                  color: t.ink,
                  onTap: chat.stop,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: t.bg,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                )
              else
                _RoundButton(
                  label: 'Send',
                  color: canSend ? t.accent : t.off,
                  onTap: canSend ? send : null,
                  child: NilsIcon(
                    'send',
                    size: IconSize.small,
                    color: t.onaccent,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.color,
    required this.onTap,
    required this.child,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tappable(
    label: label,
    tooltip: label,
    onTap: onTap,
    radius: BorderRadius.circular(Sizes.control),
    color: color,
    child: SizedBox.square(dimension: 34, child: Center(child: child)),
  );
}

/// In place of the composer until a key is saved.
class _NoKey extends StatelessWidget {
  const _NoKey();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final style = Type.sans(14, color: t.warnfg, height: 1.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: t.warnbg,
        borderRadius: BorderRadius.circular(Sizes.card),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 12,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text.rich(
              TextSpan(
                style: style,
                children: [
                  TextSpan(
                    text: 'No AnythingLLM API key yet. ',
                    style: style.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const TextSpan(
                    text:
                        'Nilson talks to AnythingLLM and needs its developer API key. '
                        'Add it in Settings to start asking.',
                  ),
                ],
              ),
            ),
          ),
          NilsButton(
            'Open Settings',
            primary: true,
            onPressed: scope.shell.openSettings,
          ),
        ],
      ),
    );
  }
}
