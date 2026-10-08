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

/// Whether an answer's reasoning shows above it, and what shows or hides it.
typedef ReasoningToggle = ({bool shown, VoidCallback toggle});

/// More, under a finished answer the server measured or that has reasoning: its menu, This
/// answer, names the answer's model, time, tokens, speed and cost, as far as [metrics] has them,
/// then View reasoning when there is [reasoning], then Show details under every answer,
/// [ChatSwitch.answerDetails], when there are [metrics]. With that switch on, the whole line of
/// them follows the button. The menu opens over the button and closes on Esc, Back, a tap
/// outside and View reasoning.
class AnswerMore extends StatefulWidget {
  const AnswerMore(this.turn, this.metrics, {super.key, this.reasoning});

  final Turn turn;

  /// How the answer ran, or null when the server did not measure it.
  final AnswerMetrics? metrics;

  /// The answer's reasoning, or null when it has none.
  final ReasoningToggle? reasoning;

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
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupAnchor(
              open: open,
              above: true,
              onClose: () => shell.closePopup(widget.turn),
              menu: (context) => _AnswerMenu(
                metrics,
                reasoning: switch (widget.reasoning) {
                  final r? => (
                    shown: r.shown,
                    toggle: () {
                      shell.closePopup(widget.turn);
                      r.toggle();
                    },
                  ),
                  null => null,
                },
              ),
              child: Tappable(
                touchTarget: true,
                label: metrics != null
                    ? 'More for this answer: model, time, tokens, speed and cost'
                    : 'More for this answer',
                tooltip: 'More',
                expanded: open,
                onTap: () => shell.togglePopup(widget.turn),
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
                  metrics.text,
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

/// The menu More opens: how the answer ran, View or Hide reasoning, then the switch that shows
/// how each answer ran under it.
class _AnswerMenu extends StatelessWidget {
  const _AnswerMenu(this.metrics, {required this.reasoning});

  final AnswerMetrics? metrics;
  final ReasoningToggle? reasoning;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final prefs = AppScope.of(context).prefs;
    final metrics = this.metrics;
    final reasoning = this.reasoning;
    return SizedBox(
      width: 248,
      child: AppMenu(
        label: 'This answer',
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: SectionLabel('This answer'),
          ),
          for (final (name, value)
              in metrics?.named ?? const <(String, String)>[])
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
          if (metrics != null) const MenuDivider(),
          if (reasoning != null)
            AppMenuItem(
              reasoning.shown ? 'Hide reasoning' : 'View reasoning',
              onTap: reasoning.toggle,
            ),
          if (metrics != null)
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
