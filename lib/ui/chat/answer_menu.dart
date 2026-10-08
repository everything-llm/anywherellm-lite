import 'package:flutter/material.dart';

import '../../core/outputs.dart';
import '../../core/prefs.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../state/chat_controller.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/controls.dart';
import '../widgets/menu.dart';
import '../widgets/tappable.dart';

/// More, under a finished answer the server measured: its menu, This answer, names the answer's
/// model, time, tokens, speed and cost, as far as [metrics] has them, over Show details under
/// every answer, [ChatSwitch.answerDetails]. With that switch on, the whole line of them follows
/// the button. The menu opens over the button and closes on Esc, Back and a tap outside.
class AnswerMore extends StatefulWidget {
  const AnswerMore(this.turn, this.metrics, {super.key});

  final Turn turn;
  final AnswerMetrics metrics;

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
    // close. Not while the tree is being torn down: the shell then hears it after the frame.
    final shell = _shell;
    final turn = widget.turn;
    if (identical(shell.answerMenu, turn)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => shell.closeAnswerMenu(turn),
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
      listenable: Listenable.merge([shell, scope.prefs]),
      builder: (context, _) {
        final open = identical(shell.answerMenu, widget.turn);
        final details = scope.prefs.prefs.isOn(ChatSwitch.answerDetails);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupAnchor(
              open: open,
              above: true,
              onClose: () => shell.closeAnswerMenu(widget.turn),
              menu: (context) => _AnswerMenu(widget.metrics),
              child: Tappable(
                touchTarget: true,
                label:
                    'More for this answer: model, time, tokens, speed and cost',
                tooltip: 'More',
                expanded: open,
                onTap: () => shell.toggleAnswerMenu(widget.turn),
                radius: BorderRadius.circular(6),
                color: open ? t.hover : null,
                child: SizedBox.square(
                  dimension: 30,
                  child: Center(
                    child: AppIcon('more', size: IconSize.small, color: t.ink2),
                  ),
                ),
              ),
            ),
            if (details) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  widget.metrics.text,
                  style: Type.sans(12, color: t.muted),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The menu More opens: how the answer ran, then the switch that shows it under every answer.
class _AnswerMenu extends StatelessWidget {
  const _AnswerMenu(this.metrics);

  final AnswerMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final prefs = AppScope.of(context).prefs;
    return SizedBox(
      width: 248,
      child: AppMenu(
        label: 'This answer',
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: SectionLabel('This answer'),
          ),
          for (final (name, value) in metrics.named)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: Type.sans(13, color: t.muted)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: Type.sans(13, color: t.ink),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Container(height: 1, color: t.line2),
          ),
          ListenableBuilder(
            listenable: prefs,
            builder: (context, _) {
              final on = prefs.prefs.isOn(ChatSwitch.answerDetails);
              const label = 'Show details under every answer';
              return Tappable(
                label: label,
                toggled: on,
                onTap: () => prefs.setSwitch(ChatSwitch.answerDetails, !on),
                radius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: Type.sans(13.5, color: t.ink),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SwitchTrack(value: on),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
