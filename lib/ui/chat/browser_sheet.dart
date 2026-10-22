import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../../core/json.dart';
import '../app_scope.dart';
import '../apps/app_view.dart';
import '../icons.dart';
import '../links.dart';
import '../state/chat_controller.dart';
import '../state/turn.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/controls.dart';
import '../widgets/fields.dart';
import '../widgets/sheet.dart';
import '../widgets/buttons.dart';
import 'composer.dart';

/// The channel browser-lean's page posts to: who has the tab, and when a hand back has gone.
const browserChannel = 'AnywhereLLMBrowser';

/// The agent's browser: browser-lean's page for its tab, in a tall sheet over the chat, edge to
/// edge under the drag handle, and under it [AgentBar], for messaging the agent. The page draws
/// its own controls: who has the tab, its address, Logins and taking it over; inside the app it
/// leaves handing back to the bar. Its Back, Esc, Back on the device, the scrim and a drag down
/// close the sheet.
class BrowserSheet extends StatefulWidget {
  const BrowserSheet(this.tab, {super.key});

  final Uri tab;

  @override
  State<BrowserSheet> createState() => _BrowserSheetState();
}

class _BrowserSheetState extends State<BrowserSheet> {
  late final _channel = PageChannel(browserChannel, _heard);

  /// Whether the person has the tab, as the page last said.
  bool _mine = false;

  /// Whether the tab's page failed to load, which leaves nobody to message.
  bool _gone = false;

  /// The hand back asked for, which completes once the page has posted it.
  Completer<void>? _giving;

  void _heard(String message) {
    switch (jsonOrNull(message)) {
      case {'gave': true}:
        if (_giving case final giving? when !giving.isCompleted) {
          giving.complete();
        }
      case {'who': final String who} when (who == 'user') != _mine:
        setState(() => _mine = who == 'user');
    }
  }

  /// Hands the tab back to the agent, waiting at most a few seconds for the page to post it.
  Future<void> _give() async {
    if (!_mine) return;
    final giving = _giving = Completer<void>();
    setState(() => _mine = false);
    await _channel.run('window.browserLean&&browserLean.give()');
    await giving.future.timeout(const Duration(seconds: 4), onTimeout: () {});
    if (_giving == giving) _giving = null;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final view = scope.appView;
    return SheetFrame(
      title: 'The agent’s browser',
      bare: true,
      height: SheetHeight.tall,
      padding: EdgeInsets.zero,
      onClose: scope.shell.closeBrowser,
      child: view == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: view.show(
                    widget.tab,
                    onLeave: (url) => openLink(context, url),
                    onClose: scope.shell.closeBrowser,
                    onFailed: () => setState(() => _gone = true),
                    channel: _channel,
                  ),
                ),
                if (!_gone) AgentBar(mine: _mine, onGive: _give),
              ],
            ),
    );
  }
}

/// Under the agent's browser: a message for the agent, sent in the chat under the sheet, with
/// the answer to it over the field until it is dismissed. While the person has the tab, Send
/// reads Hand back with nothing typed, and a message hands the tab back before it goes.
class AgentBar extends StatefulWidget {
  const AgentBar({super.key, required this.mine, required this.onGive});

  /// Whether the person has the tab.
  final bool mine;
  final Future<void> Function() onGive;

  @override
  State<AgentBar> createState() => _AgentBarState();
}

class _AgentBarState extends State<AgentBar> {
  final _draft = TextEditingController();

  /// Whether nothing is typed, which turns Send into Hand back while the person has the tab.
  bool _empty = true;

  /// The message sent from here and its answer, until dismissed.
  (String, Turn)? _said;

  @override
  void initState() {
    super.initState();
    _draft.addListener(() {
      final empty = _draft.text.trim().isEmpty;
      if (empty != _empty) setState(() => _empty = empty);
    });
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final chat = AppScope.of(context).chat;
    final text = _draft.text.trim();
    if (!chat.canSend(text)) return;
    _draft.clear();
    await widget.onGive();
    if (!mounted) return;
    if (!chat.canSend(text)) {
      // Not sent, so it stays to send again, unless something was typed meanwhile.
      if (_draft.text.isEmpty) _draft.text = text;
      return;
    }
    // The answer is in the chat's turns as soon as the message is taken.
    unawaited(chat.send(text));
    setState(() => _said = (text, chat.turns.last));
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final chat = AppScope.of(context).chat;
    OutlineInputBorder edge(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
      borderSide: BorderSide(color: color),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_said case (final question, final answer)) ...[
            _Said(
              question,
              answer,
              onDismiss: () => setState(() => _said = null),
            ),
            const SizedBox(height: 10),
          ],
          ListenableBuilder(
            listenable: chat,
            builder: (context, _) => Row(
              children: [
                Expanded(
                  child: FieldName(
                    label: 'Message the agent',
                    child: TextField(
                      controller: _draft,
                      enabled: !chat.busy,
                      textInputAction: TextInputAction.send,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _send(),
                      style: Type.sans(16, color: t.ink),
                      cursorColor: t.accent,
                      decoration: InputDecoration(
                        hintText: chat.busy
                            ? 'Answering…'
                            : 'Message the agent…',
                        hintStyle: Type.sans(16, color: t.muted),
                        filled: true,
                        fillColor: t.panel,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        enabledBorder: edge(t.edge),
                        disabledBorder: edge(t.edge),
                        focusedBorder: edge(t.ink),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _button(chat, t),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Stop while this chat answers, Hand back while the person has the tab and nothing is
  /// typed, and otherwise Send.
  Widget _button(ChatController chat, Tokens t) {
    if (chat.answeringHere) {
      return RoundButton(
        label: 'Stop the answer',
        color: t.ink,
        onTap: chat.stop,
        size: 44,
        child: const StopMark(),
      );
    }
    if (widget.mine && !chat.busy && _empty) {
      return RoundButton(
        label: 'Hand back to the agent',
        color: t.accent,
        onTap: widget.onGive,
        size: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            'Hand back',
            style: Type.sans(15, weight: FontWeight.w600, color: t.onaccent),
          ),
        ),
      );
    }
    final sendable = chat.canSend(_draft.text);
    return RoundButton(
      label: 'Send to the agent',
      color: sendable ? t.accent : t.off,
      onTap: sendable ? _send : null,
      size: 44,
      child: AppIcon(
        'send',
        size: IconSize.small,
        color: sendable ? t.onaccent : t.muted,
      ),
    );
  }
}

/// The message sent from the bar and the answer to it as it streams, its reasoning left out.
class _Said extends StatelessWidget {
  const _Said(this.question, this.answer, {required this.onDismiss});

  final String question;
  final Turn answer;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: answer,
      builder: (context, _) {
        final text = splitReasoning(
          answer.text,
          streaming: answer.streaming,
        ).answer.trim();
        return Container(
          constraints: const BoxConstraints(maxHeight: 84),
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.line2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You: $question',
                          style: Type.sans(13, color: t.muted),
                        ),
                        const SizedBox(height: 4),
                        if (answer.error case final error?)
                          Text(error, style: Type.sans(14.5, color: t.badfg))
                        else if (text.isNotEmpty)
                          Text(
                            text,
                            style: Type.sans(14.5, color: t.ink, height: 1.45),
                          )
                        else if (answer.status case final status?)
                          Text(status, style: Type.sans(14.5, color: t.muted)),
                        if (answer.streaming) const Caret(),
                      ],
                    ),
                  ),
                ),
              ),
              IconBtn(
                'close',
                tooltip: 'Dismiss the reply',
                onPressed: onDismiss,
                box: 28,
                size: IconSize.small,
              ),
            ],
          ),
        );
      },
    );
  }
}
