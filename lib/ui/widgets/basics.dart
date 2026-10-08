import 'package:flutter/material.dart';

import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// What a box says: a warning, a failure, or a calm note of something under way, which has
/// an accent dot by its title.
enum AlertKind { warn, bad, info }

class AlertBox extends StatelessWidget {
  const AlertBox(this.kind, this.title, {super.key, this.text});

  final AlertKind kind;
  final String title;
  final String? text;

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
      style: Type.sans(14, weight: FontWeight.w600, color: ink),
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
          borderRadius: BorderRadius.circular(Sizes.card),
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
  const UndoBar(this.text, {super.key, required this.onUndo});

  final String text;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(
          color: t.ink,
          borderRadius: BorderRadius.circular(Sizes.control),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.sans(13, color: t.bg),
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
                  style: Type.sans(13, weight: FontWeight.w600, color: t.bg),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small capitalised heading over a group, as over the files and in Settings.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text.toUpperCase(),
      style: Type.sans(
        12,
        weight: FontWeight.w500,
        color: Tokens.of(context).muted,
        letterSpacing: 12 * 0.04,
      ),
    ),
  );
}

/// A sidebar group's heading: a rule above, the [label], and one small [action] at the end.
class SidebarSection extends StatelessWidget {
  const SidebarSection(this.label, {super.key, required this.action});

  final String label;
  final Widget action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 14, 4, 6),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Tokens.of(context).line)),
    ),
    child: Row(
      children: [
        Expanded(child: SectionLabel(label)),
        action,
      ],
    ),
  );
}
