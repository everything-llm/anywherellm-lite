import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:path_drawing/path_drawing.dart';

import '../../core/prefs.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../state/chat_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/buttons.dart';
import '../widgets/rise.dart';
import '../widgets/tappable.dart';
import 'question_body.dart';

/// The messages waiting in the chat on screen, under its newest answer: a line over them that
/// says when they go, with Resume while they are held and Clear all, then each as a bubble with
/// a dashed edge, which a tap puts back in the message box ([onPutBack]), over when it goes and
/// Don't send, 16 under the answer. Nothing while none waits.
class OnDeckView extends StatelessWidget {
  const OnDeckView({super.key, required this.onPutBack});

  /// Puts a waiting message back in the message box, ahead of what is typed there.
  final ValueChanged<OnDeck> onPutBack;

  /// What the line over [count] waiting messages says, [held] or not.
  static String headOf(int count, {required bool held}) => held
      ? 'Paused · $count waiting'
      : count == 1
      ? 'Sends when this answer ends.'
      : count > 10
      ? '$count waiting · a long queue'
      : 'Each sends in turn, when the answer before it ends.';

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final items = chat.onDeck;
    if (items.isEmpty) return const SizedBox.shrink();
    final held = chat.onDeckHeld;
    final hide = scope.prefs.prefs.isOn(ChatSwitch.hideShortcutPrompts);
    final view = Semantics(
      container: true,
      explicitChildNodes: true,
      label: '${items.length} waiting to send',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: 4,
        children: [
          _BleedEnd(
            child: Row(
              spacing: 8,
              children: [
                Expanded(child: _RuledLine(headOf(items.length, held: held))),
                if (held) _LineButton('Resume', chat.resumeOnDeck),
                _LineButton('Clear all', chat.clearOnDeck),
              ],
            ),
          ),
          for (final (i, item) in items.indexed)
            _Waiting(
              item,
              key: ObjectKey(item),
              when: held
                  ? 'Paused'
                  : i == 0
                  ? 'Next'
                  : 'Waiting',
              compact: hide,
              onPutBack: () => onPutBack(item),
              onDrop: () => chat.dropOnDeck(item),
            ),
        ],
      ),
    );
    // Apart from the answer over it, whose caret and stream repaint it many times a second.
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: RepaintBoundary(child: view),
    );
  }
}

/// [child] 12 wider than the room it is given, reaching 12 past its end edge, so the words of
/// the buttons at its end line up with that edge, as the padding of their touch target is past
/// it. That 12 is drawn but not tapped.
class _BleedEnd extends StatelessWidget {
  const _BleedEnd({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => OverflowBox(
      alignment: AlignmentDirectional.centerStart,
      minWidth: box.maxWidth + 12,
      maxWidth: box.maxWidth + 12,
      fit: OverflowBoxFit.deferToChild,
      child: child,
    ),
  );
}

/// [text] at the end of a 1 px rule that fills the room before it. The rule gives way to the
/// text, which wraps once the room is too narrow for it on one line.
class _RuledLine extends StatelessWidget {
  const _RuledLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Stack(
      alignment: AlignmentDirectional.centerEnd,
      children: [
        Positioned.fill(
          child: Center(child: Container(height: 1, color: t.line)),
        ),
        // On the chat's ground, so the rule stops 8 short of the words.
        Container(
          color: t.ground,
          padding: const EdgeInsetsDirectional.only(start: 8),
          child: Semantics(
            liveRegion: true,
            child: Text(text, style: Type.note(t.ink)),
          ),
        ),
      ],
    );
  }
}

/// A button in the line over the waiting messages: its words in the accent, 44 tall.
class _LineButton extends StatelessWidget {
  const _LineButton(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tappable(
    label: label,
    onTap: onTap,
    radius: BorderRadius.circular(6),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(label, style: Type.caption(Tokens.of(context).accent)),
        ),
      ),
    ),
  );
}

/// One waiting message: a sent message's bubble with no fill and a dashed edge, which a tap
/// puts back in the message box, over a clock with [when] it goes and Don't send.
class _Waiting extends StatelessWidget {
  const _Waiting(
    this.item, {
    super.key,
    required this.when,
    required this.compact,
    required this.onPutBack,
    required this.onDrop,
  });

  final OnDeck item;

  /// Next, Waiting or Paused.
  final String when;

  /// Whether a message written with a shortcut shows the shortcut in place of its prompt.
  final bool compact;
  final VoidCallback onPutBack;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Rise(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: questionWidth),
            child: Tappable(
              label: 'Edit ${item.text}',
              onTap: onPutBack,
              radius: questionRadius,
              child: CustomPaint(
                foregroundPainter: _DashedEdge(t.lineStrong),
                child: Padding(
                  padding: questionPadding,
                  child: QuestionBody(
                    item.text,
                    attachments: item.files,
                    shortcutUse: compact ? item.shortcutUse : null,
                    lost: item.lost,
                  ),
                ),
              ),
            ),
          ),
          // Don't send's target is 44 wide, so the line reaches 12 past the bubble's edge.
          Transform.translate(
            offset: const Offset(12, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon('clock', size: IconSize.note, color: t.ink),
                const SizedBox(width: 6),
                Text(when, style: Type.note(t.ink)),
                IconBtn(
                  'close',
                  tooltip: "Don't send",
                  heard: "Don't send ${item.text}",
                  onPressed: onDrop,
                  box: 44,
                  size: IconSize.xs,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A question bubble's edge, 1.5 wide in [color], dashed.
class _DashedEdge extends CustomPainter {
  _DashedEdge(this.color);

  final Color color;

  static const _width = 1.5;
  static const _dash = 4.5;
  static const _gap = 4.5;

  @override
  void paint(Canvas canvas, Size size) {
    final edge = questionRadius.toRRect(Offset.zero & size).deflate(_width / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width;
    canvas.drawPath(
      dashPath(
        Path()..addRRect(edge),
        dashArray: CircularIntervalList<double>([_dash, _gap]),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_DashedEdge old) => old.color != color;
}
