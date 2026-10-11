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
import '../settings/rows.dart';
import '../widgets/menu.dart';
import '../widgets/sheet.dart';
import '../widgets/tappable.dart';

/// The circle an answer's action button takes and its icon's size: 44 on a phone, where the
/// design canvas sets the buttons side by side, and 30 elsewhere.
({double box, IconSize icon}) answerAction(BuildContext context) =>
    ScreenClass.ofContext(context).isPhone
    ? (box: 44, icon: IconSize.xs)
    : (box: 30, icon: IconSize.xs);

/// More, under a finished answer the server measured or that can be rated:
/// its menu, This answer, names the answer's model, time, tokens, speed and cost, as far as
/// [metrics] has them, then Rate this answer when [rate] can, then Show details under every answer, [ChatSwitch.answerDetails], when there
/// are [metrics]. With that switch on, the whole line of them follows the button. The menu opens
/// over the button, or as a sheet over the chat on a phone, and closes on Esc, Back and a tap
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
        final button = Tappable(
          touchTarget: true,
          label: metrics != null
              ? 'More for this answer: model, time, tokens, speed and cost'
              : 'More for this answer',
          tooltip: 'More',
          expanded: open,
          onTap: () => shell.togglePopup(widget.turn),
          shape: const CircleBorder(),
          color: open ? t.hover : null,
          child: SizedBox.square(
            dimension: answerAction(context).box,
            child: Center(
              child: AppIcon(
                'more',
                size: answerAction(context).icon,
                color: t.ink2,
              ),
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
                sheet: (context) => _AnswerMenu(
                  widget.turn,
                  metrics,
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
                menu: (context) =>
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

/// The menu More opens, or the sheet on a phone: how the answer ran, Rate this answer, then the switch that shows how each answer ran under it.
class _AnswerMenu extends StatelessWidget {
  const _AnswerMenu(
    this.turn,
    this.metrics, {
    required this.rate,
    this.sheet = false,
  });

  final Turn turn;
  final AnswerMetrics? metrics;
  final ChatController? rate;

  /// Drawn in a sheet, at a phone's sizes, rather than as a menu.
  final bool sheet;

  /// A phone's sheet: the figures in one card, Rate this answer in another, and the switch in
  /// a third.
  Widget _cards(BuildContext context) {
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
            FieldCard(inSheet: true, [
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
            FieldCard(inSheet: true, [
              ListenableBuilder(
                listenable: turn,
                builder: (context, _) => Container(
                  constraints: const BoxConstraints(minHeight: 64),
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
            FieldCard(inSheet: true, [
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
                      large: true,
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

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final prefs = AppScope.of(context).prefs;
    final metrics = this.metrics;
    final rate = this.rate;
    if (sheet) return _cards(context);
    const text = 13.0;
    const row = 40.0;
    const pad = 10.0;
    final rows = <Widget>[
      const Padding(
        padding: EdgeInsets.fromLTRB(10, 6, 10, 4),
        child: SectionLabel('This answer'),
      ),
      for (final (name, value) in metrics?.named ?? const <(String, String)>[])
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad, vertical: 5),
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
                      style: Type.sans(13.5, color: t.ink),
                    ),
                  ),
                  for (final good in const [true, false])
                    IconBtn(
                      good ? 'thumb-up' : 'thumb-down',
                      tooltip: good ? 'Good answer' : 'Bad answer',
                      active: turn.feedback == good,
                      onPressed: () => rate.mark(turn, good),
                      box: 30,
                      size: IconSize.xs,
                    ),
                ],
              ),
            ),
          ),
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
    ];
    return SizedBox(
      width: 248,
      child: AppMenu(label: 'This answer', children: rows),
    );
  }
}
