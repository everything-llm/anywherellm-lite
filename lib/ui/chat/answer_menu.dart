import 'package:flutter/material.dart';

import '../../core/outputs.dart';
import '../../core/prefs.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../state/chat_controller.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/menu.dart';
import '../widgets/sheet.dart';
import '../widgets/tappable.dart';

/// Whether an answer's reasoning shows above it, and what shows or hides it.
typedef ReasoningToggle = ({bool shown, VoidCallback toggle});

/// More, under a finished answer the server measured, that has reasoning or that can be rated:
/// its menu, This answer, names the answer's model, time, tokens, speed and cost, as far as
/// [metrics] has them, then Rate this answer when [rate] can, then View reasoning when there is
/// [reasoning], then Show details under every answer, [ChatSwitch.answerDetails], when there
/// are [metrics]. With that switch on, the whole line of them follows the button. The menu opens
/// over the button, or as a sheet over the chat on a phone, and closes on Esc, Back, a tap
/// outside and View reasoning.
class AnswerMore extends StatefulWidget {
  const AnswerMore(
    this.turn,
    this.metrics, {
    super.key,
    this.reasoning,
    this.rate,
  });

  final Turn turn;

  /// The chat that marks the answer good or bad, or null when it cannot be marked.
  final ChatController? rate;

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
        final reasoning = switch (widget.reasoning) {
          final r? => (
            shown: r.shown,
            toggle: () {
              shell.closePopup(widget.turn);
              r.toggle();
            },
          ),
          null => null,
        };
        void close() => shell.closePopup(widget.turn);
        final button = Tappable(
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
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ScreenClass.ofContext(context).isPhone)
              PopupSheet(
                open: open,
                onClose: close,
                title: 'This answer',
                maxFraction: 0.7,
                sheet: (context) => _AnswerMenu(
                  widget.turn,
                  metrics,
                  reasoning: reasoning,
                  rate: widget.rate,
                  sheet: true,
                ),
                child: button,
              )
            else
              PopupAnchor(
                open: open,
                above: true,
                onClose: close,
                menu: (context) => _AnswerMenu(
                  widget.turn,
                  metrics,
                  reasoning: reasoning,
                  rate: widget.rate,
                ),
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

/// The menu More opens, or the sheet on a phone: how the answer ran, Rate this answer, View or
/// Hide reasoning, then the switch that shows how each answer ran under it.
class _AnswerMenu extends StatelessWidget {
  const _AnswerMenu(
    this.turn,
    this.metrics, {
    required this.reasoning,
    required this.rate,
    this.sheet = false,
  });

  final Turn turn;
  final AnswerMetrics? metrics;
  final ReasoningToggle? reasoning;
  final ChatController? rate;

  /// Drawn in a sheet, at a phone's sizes, rather than as a menu.
  final bool sheet;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final prefs = AppScope.of(context).prefs;
    final metrics = this.metrics;
    final reasoning = this.reasoning;
    final rate = this.rate;
    final text = sheet ? 14.5 : 13.0;
    final row = sheet ? 44.0 : 40.0;
    final pad = sheet ? 4.0 : 10.0;
    final rows = <Widget>[
      if (!sheet)
        const Padding(
          padding: EdgeInsets.fromLTRB(10, 6, 10, 4),
          child: SectionLabel('This answer'),
        ),
      for (final (name, value) in metrics?.named ?? const <(String, String)>[])
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: pad,
            vertical: sheet ? 8 : 5,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Type.sans(text, color: t.muted)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: Type.sans(text, color: t.ink),
                ),
              ),
            ],
          ),
        ),
      if (metrics != null) const MenuDivider(),
      if (rate != null)
        ListenableBuilder(
          listenable: turn,
          builder: (context, _) => ConstrainedBox(
            constraints: BoxConstraints(minHeight: row),
            child: Padding(
              padding: EdgeInsets.only(left: pad),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Rate this answer',
                      style: Type.sans(sheet ? 14.5 : 13.5, color: t.ink),
                    ),
                  ),
                  for (final good in const [true, false])
                    IconBtn(
                      good ? 'thumb-up' : 'thumb-down',
                      tooltip: good ? 'Good answer' : 'Bad answer',
                      active: turn.feedback == good,
                      onPressed: () => rate.mark(turn, good),
                      box: sheet ? 44 : 30,
                      size: sheet ? IconSize.small : IconSize.xs,
                    ),
                ],
              ),
            ),
          ),
        ),
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
                constraints: BoxConstraints(minHeight: row),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: Type.sans(sheet ? 14.5 : 13.5, color: t.ink),
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
    ];
    if (sheet) {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      );
    }
    return SizedBox(
      width: 248,
      child: AppMenu(label: 'This answer', children: rows),
    );
  }
}
