import 'package:flutter/material.dart';

import '../layout.dart';
import '../tokens.dart';
import '../type.dart';

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
