import 'package:flutter/material.dart';

import '../../core/outputs.dart';
import '../../core/prefs.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../state/chat_controller.dart';
import '../state/shell_controller.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../settings/rows.dart';
import '../widgets/sheet.dart';

/// The circle an answer's action button takes, its icon at [IconSize.xs], as the design canvas
/// sets the buttons side by side.
const answerAction = 44.0;

/// More, under a finished answer the server measured or that can be rated: its sheet, This
/// answer, names the answer's model, time, tokens, speed and cost, as far as [metrics] has them,
/// then Rate this answer when [rate] can, then Show details under every answer,
/// [ChatSwitch.answerDetails], when there are [metrics]. With that switch on, the whole line of
/// them follows the button. The sheet opens over the chat, and closes on Esc, Back and a tap
/// outside.
class AnswerMore extends StatefulWidget {
  const AnswerMore(this.turn, this.metrics, {super.key, this.rate});

  final Turn turn;

  /// The chat that marks the answer good or bad, or null when it cannot be marked.
  final ChatController? rate;

  /// How the answer ran, or null when the server did not measure it.
  final AnswerMetrics? metrics;

  @override
  State<AnswerMore> createState() => _AnswerMoreState();
}

class _AnswerMoreState extends State<AnswerMore> {
  late final ShellController _shell;

  @override
  void initState() {
    super.initState();
    _shell = AppScope.of(context).shell;
  }

  @override
  void dispose() {
    // An answer that leaves the screen takes its menu with it, so Back has nothing hidden to
    // close. Not while the tree is being torn down: the popup closes after the frame.
    final (shell, turn) = (_shell, widget.turn);
    if (identical(shell.popup.value, turn)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => shell.closePopup(turn),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([shell.popup, scope.prefs]),
      builder: (context, _) {
        final open = identical(shell.popup.value, widget.turn);
        final metrics = widget.metrics;
        final details =
            metrics != null && scope.prefs.prefs.isOn(ChatSwitch.answerDetails);
        void close() => shell.closePopup(widget.turn);
        final button = IconBtn(
          'more',
          tooltip: 'More',
          heard: metrics != null
              ? 'More for this answer: model, time, tokens, speed and cost'
              : 'More for this answer',
          expanded: open,
          filled: open,
          onPressed: () => shell.togglePopup(widget.turn),
          box: answerAction,
          size: IconSize.xs,
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupSheet(
              open: open,
              onClose: close,
              title: 'This answer',
              sheet: (context) =>
                  _AnswerMenu(widget.turn, metrics, rate: widget.rate),
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

/// The sheet More opens: the figures of how the answer ran in one card, Rate this answer in
/// another, and the switch that shows how each answer ran under it in a third.
class _AnswerMenu extends StatelessWidget {
  const _AnswerMenu(this.turn, this.metrics, {required this.rate});

  final Turn turn;
  final AnswerMetrics? metrics;
  final ChatController? rate;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final prefs = AppScope.of(context).prefs;
    final metrics = this.metrics;
    final rate = this.rate;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          if (metrics != null && metrics.named.isNotEmpty)
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
          if (rate != null)
            FieldCard([
              ListenableBuilder(
                listenable: turn,
                builder: (context, _) => Container(
                  constraints: const BoxConstraints(minHeight: Sizes.cardRow),
                  padding: const EdgeInsets.only(
                    left: FieldCard.inset,
                    right: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Rate this answer',
                          style: Type.sans(17, color: t.ink),
                        ),
                      ),
                      for (final good in const [true, false])
                        IconBtn(
                          good ? 'thumb-up' : 'thumb-down',
                          tooltip: good ? 'Good answer' : 'Bad answer',
                          active: turn.feedback == good,
                          onPressed: () => rate.mark(turn, good),
                          box: 44,
                          size: IconSize.small,
                        ),
                    ],
                  ),
                ),
              ),
            ]),
          if (metrics != null)
            FieldCard([
              ListenableBuilder(
                listenable: prefs,
                builder: (context, _) {
                  final on = prefs.prefs.isOn(ChatSwitch.answerDetails);
                  return FieldRow(
                    label: 'Show details under every answer',
                    small: true,
                    control: AppSwitch(
                      value: on,
                      label: 'Show details under every answer',
                      onChanged: (on) =>
                          prefs.setSwitch(ChatSwitch.answerDetails, on),
                    ),
                  );
                },
              ),
            ]),
        ],
      ),
    );
  }
}
