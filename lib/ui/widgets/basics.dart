import 'package:flutter/material.dart';

import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// What a box says: a warning, a failure, or a calm note of something under way, which has
/// an accent dot by its title.
enum AlertKind { warn, bad, info }

class AlertBox extends StatelessWidget {
  const AlertBox(
    this.kind,
    this.title, {
    super.key,
    this.text,
    this.action,
    this.plain = false,
  });

  final AlertKind kind;
  final String title;
  final String? text;

  /// Draws [title] at regular weight, for a box whose title is its whole message, such as a
  /// question asked before a delete.
  final bool plain;

  /// A button under the text, such as the one that asks again.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final (fill, border, ink, body) = switch (kind) {
      AlertKind.bad => (t.badbg, Border.all(color: t.badln), t.badfg, t.badfg),
      AlertKind.warn => (t.warnbg, null, t.warnfg, t.warnfg),
      AlertKind.info => (t.accentbg, null, t.ink, t.ink2),
    };
    final heading = Text(
      title,
      style: plain
          ? Type.sans(14, color: ink, height: 1.45)
          : Type.sans(14, weight: FontWeight.w600, color: ink),
    );
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
              Text(text!, style: Type.sans(14, color: body)),
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

  /// Over a phone's chat: rounder, its words at 14 and centred, Undo bold and underlined.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final size = floating ? 14.0 : 13.0;
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
                    color: t.shadow,
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
                style: Type.sans(size, color: t.bg),
              ),
            ),
            Tappable(
              label: 'Undo',
              onTap: onUndo,
              radius: BorderRadius.circular(6),
              hoverColor: t.bg.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Text(
                  'Undo',
                  style:
                      Type.sans(
                        size,
                        weight: floating ? FontWeight.w700 : FontWeight.w600,
                        color: t.bg,
                      ).copyWith(
                        decoration: floating ? TextDecoration.underline : null,
                        decorationColor: t.bg,
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

/// A small capitalised heading over a group, as over the files and in Settings, or over a
/// column of a card's rows. It keeps to one line.
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
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: end ? TextAlign.end : TextAlign.start,
      style: Type.sans(
        12,
        weight: FontWeight.w500,
        color: Tokens.of(context).muted,
        letterSpacing: 12 * 0.04,
      ),
    ),
  );
}
