import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../state/notice.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// What a box says: a warning, a failure, or a calm note of something under way, which has
/// an accent dot by its title. A warning and a failure carry House UI's status icon by their
/// title, and their words are in ink, so the colour never says it alone.
enum AlertKind { warn, bad, info }

/// House UI's states, each with its own icon: a circle with a check, a triangle, a square with
/// a cross, which differ in shape as well as colour.
enum Status {
  success('success'),
  warning('warning'),
  danger('danger');

  const Status(this.icon);

  /// The icon's name in the set.
  final String icon;

  /// The status's colour, for its icon only.
  Color color(Tokens t) => switch (this) {
    success => t.success,
    warning => t.warning,
    danger => t.danger,
  };
}

/// A state as House UI shows it: [status]'s icon in its colour beside [word] in [style], which
/// is in ink, or the word alone when it has no status, as Testing… has.
class StatusWord extends StatelessWidget {
  const StatusWord(this.word, {super.key, required this.status, this.style});

  final String word;
  final Status? status;

  /// The word's style; [Type.body] in ink when null.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final text = Text(word, style: style ?? Type.body(t.ink));
    final status = this.status;
    if (status == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        AppIcon(status.icon, size: IconSize.small, color: status.color(t)),
        Flexible(child: text),
      ],
    );
  }
}

class AlertBox extends StatelessWidget {
  const AlertBox(
    this.kind,
    this.title, {
    super.key,
    this.text,
    this.action,
    this.onClose,
    this.inline = false,
  });

  /// A box for [notice]: its title, over what went wrong.
  AlertBox.notice(
    this.kind,
    Notice notice, {
    super.key,
    this.action,
    this.onClose,
    this.inline = false,
  }) : title = notice.title,
       text = notice.text;

  final AlertKind kind;
  final String title;
  final String? text;

  /// A button under the text, such as the one that asks again.
  final Widget? action;

  /// Puts the box away, for one that stays until it is closed: a Close button at its end.
  final VoidCallback? onClose;

  /// Whether [title] leads [text] in one paragraph, `**No news** from the server…`, as a banner
  /// of a sentence or two reads, rather than heading it on a line of its own.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final (fill, border, status) = switch (kind) {
      AlertKind.bad => (
        t.dangerSoft,
        Border.all(color: t.danger),
        Status.danger,
      ),
      AlertKind.warn => (t.warningSoft, null, Status.warning),
      AlertKind.info => (t.accentSoft, null, null),
    };
    final ink = t.ink;
    final body = t.ink;
    // As large as the sentence under it, so it heads it rather than reading as a footnote.
    final strong = Type.body(ink, weight: FontWeight.w600);
    final heading = inline && text != null
        ? Text.rich(
            TextSpan(
              style: Type.body(body),
              children: [
                TextSpan(text: title, style: strong),
                TextSpan(text: ' $text'),
              ],
            ),
          )
        : Text(title, style: strong);
    return Semantics(
      liveRegion: kind != AlertKind.warn,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: fill,
          border: border,
          borderRadius: BorderRadius.circular(Sizes.notice),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _says(heading, body, status, t)),
            if (onClose case final onClose?) ...[
              const SizedBox(width: 8),
              CloseButtonMark(color: ink, onTap: onClose),
            ],
          ],
        ),
      ),
    );
  }

  /// The title, the sentence and the action, one under another.
  Widget _says(Widget heading, Color body, Status? status, Tokens t) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (status != null)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Level with the title's first line, 16 * 1.5 tall.
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: AppIcon(
                status.icon,
                size: IconSize.normal,
                color: status.color(t),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: heading),
          ],
        )
      else if (kind == AlertKind.info)
        Row(
          children: [
            const ReadyDot(gap: false),
            const SizedBox(width: 8),
            Expanded(child: heading),
          ],
        )
      else
        heading,
      if (text != null && !inline) ...[
        const SizedBox(height: 6),
        // What it says is a sentence or two, so it is running text.
        Text(text!, style: Type.body(body)),
      ],
      if (action case final action?) ...[
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft, child: action),
      ],
    ],
  );
}

/// Close, as a toast or a box that stays until it is closed draws it: a cross in [color],
/// heard and shown as Close, tapped in a finger's [Tappable.touchSide].
class CloseButtonMark extends StatelessWidget {
  const CloseButtonMark({super.key, required this.color, required this.onTap});

  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tappable(
    touchTarget: true,
    label: 'Close',
    tooltip: 'Close',
    onTap: onTap,
    shape: const CircleBorder(),
    hoverColor: color.withValues(alpha: 0.1),
    child: SizedBox.square(
      dimension: 36,
      child: Center(
        child: AppIcon('close', size: IconSize.small, color: color),
      ),
    ),
  );
}

/// The accent dot beside a chat or workspace whose answer finished while it was not on
/// screen, with room either side unless [gap] is false.
class ReadyDot extends StatelessWidget {
  const ReadyDot({super.key, this.gap = true});

  final bool gap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: gap ? 6 : 0),
    child: Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: Tokens.of(context).accent,
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// [ReadyDot] with the word Ready beside it at caption size in ink, as a chat or workspace
/// whose answer is ready shows it, so the dot is never the only sign.
class ReadyMark extends StatelessWidget {
  const ReadyMark({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 4,
    children: [
      const ReadyDot(gap: false),
      Text('Ready', style: Type.caption(Tokens.of(context).ink)),
    ],
  );
}

/// A dark bar saying what was just done, with Undo and Close, as after a file is removed or a
/// chat is deleted. It has no clock: it stays until the person undoes, closes or leaves, and
/// what it reports is done for good only then ([onClose]). Its words wrap.
class UndoBar extends StatelessWidget {
  const UndoBar(
    this.text, {
    super.key,
    required this.onUndo,
    required this.onClose,
    this.floating = false,
  });

  final String text;
  final VoidCallback onUndo;

  /// Puts the bar away, and with it the chance to undo.
  final VoidCallback onClose;

  /// Over a phone's chat: rounder, its words at 16 and centred, Undo underlined.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: floating
            ? const EdgeInsets.fromLTRB(16, 4, 4, 4)
            : const EdgeInsets.fromLTRB(12, 0, 0, 0),
        decoration: BoxDecoration(
          color: t.ink,
          borderRadius: BorderRadius.circular(
            floating ? Sizes.control : Sizes.small,
          ),
          boxShadow: floating
              ? [
                  BoxShadow(
                    color: t.shadowInk,
                    blurRadius: 24,
                    spreadRadius: -8,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  text,
                  textAlign: floating ? TextAlign.center : TextAlign.start,
                  style: floating ? Type.body(t.ground) : Type.note(t.ground),
                ),
              ),
            ),
            Tappable(
              touchTarget: true,
              label: 'Undo',
              onTap: onUndo,
              radius: BorderRadius.circular(6),
              hoverColor: t.ground.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Text(
                  'Undo',
                  style:
                      (floating
                              ? Type.label(t.ground)
                              : Type.caption(t.ground, weight: FontWeight.w600))
                          .copyWith(
                            decoration: floating
                                ? TextDecoration.underline
                                : null,
                            decorationColor: t.ground,
                          ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CloseButtonMark(color: t.ground, onTap: onClose),
          ],
        ),
      ),
    );
  }
}

/// A small heading over a group, as over the files and in Settings, or over a column of a
/// card's rows: [Type.caption] in ink, in sentence case. A long one wraps.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.end = false,
    this.header = true,
  });

  final String text;

  /// Whether it sits at the end of its space, over values aligned there.
  final bool end;

  /// Whether a screen reader hears it as a heading; a column's name is not one.
  final bool header;

  @override
  Widget build(BuildContext context) => Semantics(
    header: header,
    child: Text(
      text,
      textAlign: end ? TextAlign.end : TextAlign.start,
      style: Type.caption(Tokens.of(context).ink),
    ),
  );
}
