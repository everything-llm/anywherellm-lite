import 'package:flutter/material.dart';

import '../../core/outputs.dart';
import '../../core/prefs.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../state/turn.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../settings/rows.dart';
import '../shell_popup.dart';

/// The circle an answer's action button takes, its icon at [IconSize.xs], as the Lite prototype
/// sets the buttons side by side.
const answerAction = 44.0;

/// The size of an answer's action icons: Copy, Read aloud, Retry and More.
const answerActionIcon = IconSize.normal;

/// More, under a finished answer the server measured: its sheet, This answer, names the
/// answer's model, time, tokens, speed and cost, as far as [metrics] has them, then Show
/// details under every answer, [ChatSwitch.answerDetails]. With that switch on, the whole line
/// of them follows the button. The sheet opens over the chat, and closes on Esc, Back and a tap
/// outside.
class AnswerMore extends StatelessWidget {
  const AnswerMore(this.turn, this.metrics, {super.key});

  final Turn turn;

  /// How the answer ran.
  final AnswerMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([shell.popup, scope.prefs]),
      builder: (context, _) {
        final open = identical(shell.popup.value, turn);
        final details = scope.prefs.prefs.isOn(ChatSwitch.answerDetails);
        final button = IconBtn(
          'more',
          tooltip: 'More',
          heard: 'More for this answer: model, time, tokens, speed and cost',
          expanded: open,
          filled: open,
          onPressed: () => shell.togglePopup(turn),
          box: answerAction,
          size: answerActionIcon,
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // An answer that leaves the screen takes its sheet with it, so Back has nothing
            // hidden to close.
            ShellPopup(
              popup: turn,
              title: 'This answer',
              builder: (context, _) => _AnswerMenu(turn, metrics),
              child: button,
            ),
            if (details) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(metrics.text, style: Type.sans(12, color: t.muted)),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The sheet More opens: the figures of how the answer ran in one card, and the switch that
/// shows how each answer ran under it in another.
class _AnswerMenu extends StatelessWidget {
  const _AnswerMenu(this.turn, this.metrics);

  final Turn turn;
  final AnswerMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final prefs = AppScope.of(context).prefs;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          if (metrics.named.isNotEmpty)
            FieldCard([
              for (final (name, value) in metrics.named)
                Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: FieldCard.inset,
                    vertical: 8,
                  ),
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text(name, style: Type.sans(15, color: t.muted)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          value,
                          textAlign: TextAlign.end,
                          style: Type.sans(15, color: t.ink),
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
          FieldCard([
            ListenableBuilder(
              listenable: prefs,
              builder: (context, _) {
                final on = prefs.prefs.isOn(ChatSwitch.answerDetails);
                return FieldRow.toggle(
                  label: 'Show details under every answer',
                  value: on,
                  onChanged: (on) =>
                      prefs.setSwitch(ChatSwitch.answerDetails, on),
                );
              },
            ),
          ]),
        ],
      ),
    );
  }
}
