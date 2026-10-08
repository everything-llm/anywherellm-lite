import 'package:flutter/material.dart';

import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

enum AlertKind { warn, bad }

class AlertBox extends StatelessWidget {
  const AlertBox(this.kind, this.title, {super.key, this.text});

  final AlertKind kind;
  final String title;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final bad = kind == AlertKind.bad;
    final fg = bad ? t.badfg : t.warnfg;
    return Semantics(
      liveRegion: bad,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bad ? t.badbg : t.warnbg,
          border: bad ? Border.all(color: t.badln) : null,
          borderRadius: BorderRadius.circular(Sizes.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Type.sans(14, weight: FontWeight.w600, color: fg),
            ),
            if (text != null) ...[
              const SizedBox(height: 6),
              Text(text!, style: Type.sans(14, color: fg)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A calm note of something under way, with an accent dot by its [title]: not a failure, so
/// not drawn as one.
class StatusBox extends StatelessWidget {
  const StatusBox(this.title, {super.key, this.text});

  final String title;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: t.accentbg,
          borderRadius: BorderRadius.circular(Sizes.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: t.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Type.sans(14, weight: FontWeight.w600, color: t.ink),
                  ),
                ),
              ],
            ),
            if (text != null) ...[
              const SizedBox(height: 6),
              Text(text!, style: Type.sans(14, color: t.ink2)),
            ],
          ],
        ),
      ),
    );
  }
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

/// A small capitalised heading over a group, as over the workspaces and in Settings.
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
