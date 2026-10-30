import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/outputs.dart';
import '../../core/prefs.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../state/turn.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/tappable.dart';
import '../settings/rows.dart';
import '../shell_popup.dart';
import 'answer_body.dart';

/// The circle an answer's icon button takes, a finger's [Tappable.touchSide], its icon at
/// [answerActionIcon].
const answerAction = Tappable.touchSide;

/// The size of an answer's icons.
const answerActionIcon = IconSize.normal;

/// Ask again on the chat's last answer: [onPressed] is null while it cannot run, and [heard]
/// says why when the question went with files.
typedef AskAgain = ({VoidCallback? onPressed, String heard});

/// The Answer sheet's popup for each answer, kept as long as the answer is.
final _answerSheets = Expando<Object>('Answer sheet');

/// The Select text sheet's popup for each answer.
final _selectSheets = Expando<Object>('Select text');

/// The popup of [turn]'s Answer sheet, which [AnswerSheets] shows.
Object answerSheetOf(Turn turn) => _answerSheets[turn] ??= Object();

/// Under an answer: Copy and More while [shown], as the latest answer has them and an older one
/// once tapped; then, with Show details under every answer on ([ChatSwitch.answerDetails]),
/// how the answer ran. More opens the Answer sheet ([AnswerSheets]), which holds the rest one
/// step away; a failed answer has Copy alone ([more] false). With no [answer] to copy, as when
/// the model gave none, Ask again stands in their place. An answer stopped in Agent mode says
/// the server may still save it.
class AnswerActions extends StatelessWidget {
  const AnswerActions(
    this.turn, {
    super.key,
    required this.answer,
    required this.shown,
    this.askAgain,
    this.more = true,
  });

  final Turn turn;

  /// The answer's words without its reasoning, or empty when there are none.
  final String answer;
  final bool shown;
  final AskAgain? askAgain;

  /// Whether More shows beside Copy.
  final bool more;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([shell.popup, scope.prefs]),
      builder: (context, _) {
        final metrics = turn.metrics;
        final details =
            metrics != null && scope.prefs.prefs.isOn(ChatSwitch.answerDetails);
        final sheet = answerSheetOf(turn);
        final buttons = [
          if (shown && answer.isNotEmpty) ...[
            _CopyAction(answer),
            if (more)
              LabelAction(
                'More',
                end: 'down',
                heard: 'More: read aloud, ask again, details',
                expanded: identical(shell.popup.value, sheet),
                onTap: () => shell.togglePopup(sheet),
              ),
          ] else if (answer.isEmpty && askAgain != null)
            LabelAction(
              'Ask again',
              icon: 'refresh',
              heard: askAgain!.heard,
              onTap: askAgain!.onPressed,
            ),
          // In Agent mode the server may go on to finish the answer and save it, which shows
          // when the chat is read again.
          if (turn.stopped)
            Text(
              'Stopped · the server may still save it',
              style: Type.note(t.ink),
            ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (buttons.isNotEmpty)
              // Each button's words sit 8 inside its press, so the row starts 8 to the left and
              // the first icon lines up with the answer's text.
              Transform.translate(
                offset: const Offset(-8, 0),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: buttons,
                ),
              ),
            if (details) Text(metrics.text, style: Type.note(t.ink)),
          ],
        );
      },
    );
  }
}

/// A button of an answer's actions: its words semibold at body size in ink, an [icon] before
/// them or an [end] icon after, both muted, in a pill a finger's height.
class LabelAction extends StatelessWidget {
  const LabelAction(
    this.label, {
    super.key,
    required this.onTap,
    this.icon,
    this.end,
    this.heard,
    this.expanded,
  });

  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final String? end;

  /// What a screen reader hears, when it says more than [label].
  final String? heard;

  /// Whether what it opens is open, for a button that opens a sheet.
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final ink = onTap == null ? t.muted : t.ink;
    return Tappable(
      label: heard ?? label,
      onTap: onTap,
      expanded: expanded,
      excludeSemantics: true,
      radius: BorderRadius.circular(99),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Tappable.touchSide),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              if (icon case final icon?)
                AppIcon(icon, size: IconSize.small, color: t.muted),
              Flexible(
                child: Text(
                  label,
                  style: Type.sans(
                    Type.chat,
                    weight: FontWeight.w600,
                    color: ink,
                    height: 1.25,
                  ),
                ),
              ),
              if (end case final end?)
                AppIcon(end, size: IconSize.small, color: t.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Copy, which puts the answer on the clipboard; for a moment after, its icon is a check in the
/// copy's place, so no word pushes the row, and a live region says Copied to a screen reader.
class _CopyAction extends StatefulWidget {
  const _CopyAction(this.text);

  final String text;

  @override
  State<_CopyAction> createState() => _CopyActionState();
}

class _CopyActionState extends State<_CopyAction> {
  Timer? _reset;
  bool _copied = false;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: _copied ? 'Copied' : null,
    child: LabelAction(
      'Copy',
      icon: _copied ? 'check' : 'copy',
      heard: 'Copy answer',
      onTap: _copy,
    ),
  );
}

/// [child], an answer, with its sheets: Answer, which More and a long press on the answer open,
/// holding Copy, Select text, Read aloud, Ask again and Details; Select text, which shows the
/// answer's words selectable; and This answer, which Details opens, for an answer the server
/// measured. Each opens over the chat, and closes on Esc, Back and a tap outside; an answer
/// that leaves the screen takes its sheets with it, so Back has nothing hidden to close.
class AnswerSheets extends StatelessWidget {
  const AnswerSheets(
    this.turn, {
    super.key,
    required this.answer,
    required this.child,
    this.askAgain,
  });

  final Turn turn;

  /// The answer's words without its reasoning.
  final String answer;
  final AskAgain? askAgain;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final metrics = turn.metrics;
    return ShellPopup(
      popup: answerSheetOf(turn),
      title: 'Answer',
      present: answer.isNotEmpty,
      builder: (context, close) =>
          _AnswerSheet(turn, answer: answer, askAgain: askAgain, close: close),
      child: ShellPopup(
        popup: _selectSheets[turn] ??= Object(),
        title: 'Select text',
        present: answer.isNotEmpty,
        builder: (context, _) =>
            SingleChildScrollView(child: AnswerBody(answer)),
        child: ShellPopup(
          popup: turn,
          title: 'This answer',
          present: metrics != null,
          builder: (context, _) => _AnswerMenu(turn, metrics!),
          child: child,
        ),
      ),
    );
  }
}

/// The Answer sheet's rows, in one card.
class _AnswerSheet extends StatelessWidget {
  const _AnswerSheet(
    this.turn, {
    required this.answer,
    required this.askAgain,
    required this.close,
  });

  final Turn turn;
  final String answer;
  final AskAgain? askAgain;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    final aloud = scope.readAloud;
    final t = Tokens.of(context);
    return SingleChildScrollView(
      child: FieldCard([
        CardRow(
          'Copy',
          icon: 'copy',
          heard: 'Copy answer',
          onTap: () {
            unawaited(Clipboard.setData(ClipboardData(text: answer)));
            close();
          },
        ),
        CardRow(
          'Select text',
          icon: 'select',
          onTap: () => shell.togglePopup(_selectSheets[turn] ??= Object()),
        ),
        if (aloud != null)
          ListenableBuilder(
            listenable: aloud,
            builder: (context, _) {
              final reading = identical(aloud.reading, turn);
              return CardRow(
                reading ? 'Stop reading' : 'Read aloud',
                icon: reading ? 'stop' : 'speaker',
                onTap: () {
                  aloud.toggle(turn);
                  close();
                },
              );
            },
          ),
        if (askAgain case final again?)
          CardRow(
            'Ask again',
            icon: 'refresh',
            heard: again.heard,
            onTap: switch (again.onPressed) {
              final ask? => () {
                close();
                ask();
              },
              null => null,
            },
          ),
        if (turn.metrics != null)
          CardRow(
            'Details',
            icon: 'info',
            heard: 'Details: model, time, tokens, speed and cost',
            trailing: AppIcon('chevron', size: IconSize.small, color: t.muted),
            onTap: () => shell.togglePopup(turn),
          ),
      ]),
    );
  }
}

/// This answer, which Details opens: the figures of how the answer ran in one card, and the
/// switch that shows how each answer ran under it in another.
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
                      Text(name, style: Type.body(t.muted)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          value,
                          textAlign: TextAlign.end,
                          style: Type.body(t.ink),
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
