import 'package:flutter/material.dart';

import '../layout.dart';
import '../state/notice.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// What a box says: a warning, a failure, or a calm note of something under way, which has
/// an accent dot by its title.
enum AlertKind { warn, bad, info }

class AlertBox extends StatelessWidget {
  const AlertBox(this.kind, this.title, {super.key, this.text, this.action});

  /// A box for [notice]: its title, over what went wrong.
  AlertBox.notice(this.kind, Notice notice, {super.key, this.action})
    : title = notice.title,
      text = notice.text;

  final AlertKind kind;
  final String title;
  final String? text;

  /// A button under the text, such as the one that asks again.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final (fill, border, ink, body) = switch (kind) {
      AlertKind.bad => (
        t.dangerSoft,
        Border.all(color: t.danger),
        t.danger,
        t.danger,
      ),
      AlertKind.warn => (t.warningSoft, null, t.warning, t.warning),
      AlertKind.info => (t.accentSoft, null, t.ink, t.ink),
    };
    // As large as the sentence under it, so it heads it rather than reading as a footnote.
    final heading = Text(title, style: Type.body(ink, weight: FontWeight.w600));
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (kind == AlertKind.info)
              Row(
                children: [
                  const ReadyDot(gap: false),
                  const SizedBox(width: 8),
                  Expanded(child: heading),
                ],
              )
            else
              heading,
            if (text != null) ...[
              const SizedBox(height: 6),
              // What it says is a sentence or two, so it is running text.
              Text(text!, style: Type.body(body)),
            ],
            if (action case final action?) ...[
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: action),
            ],
          ],
        ),
      ),
    );
  }
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

/// A dark bar saying what was just done, with Undo, as after a file is removed or a chat is
/// deleted.
class UndoBar extends StatelessWidget {
  const UndoBar(
    this.text, {
    super.key,
    required this.onUndo,
    this.floating = false,
  });

  final String text;
  final VoidCallback onUndo;

  /// Over a phone's chat: rounder, its words at 16 and centred, Undo underlined.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: floating
            ? const EdgeInsets.fromLTRB(16, 6, 8, 6)
            : const EdgeInsets.fromLTRB(12, 4, 4, 4),
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
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: floating ? TextAlign.center : TextAlign.start,
                style: floating ? Type.body(t.ground) : Type.note(t.ground),
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
          ],
        ),
      ),
    );
  }
}

/// A small heading over a group, as over the files and in Settings, or over a column of a
/// card's rows: [Type.caption] in ink, in sentence case. It keeps to one line.
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
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: end ? TextAlign.end : TextAlign.start,
      style: Type.caption(Tokens.of(context).ink),
    ),
  );
}
