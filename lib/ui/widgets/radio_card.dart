import 'package:flutter/material.dart';

import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// One choice of several: a radio ring, [title] and the line [about] under it, in a box inside a
/// [Tokens.lineStrong] edge, filled with [Tokens.accentSoft] while chosen. A chosen title is
/// semibold.
class RadioCard extends StatelessWidget {
  const RadioCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.about,
  });

  final String title;
  final String? about;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    // The card rings itself in the selection colour when chosen, and marks the choice with a
    // thick ring rather than a dot, as the Lite prototype draws it.
    return Tappable(
      label: [title, ?about].join('. '),
      selected: selected,
      onTap: onTap,
      radius: BorderRadius.circular(Sizes.control),
      color: selected ? t.accentSoft : t.tile,
      side: BorderSide(color: selected ? t.accentSoft : t.lineStrong),
      child: Container(
        constraints: const BoxConstraints(minHeight: Sizes.cardRow),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? t.accent : t.muted,
                  width: selected ? 5 : 1.5,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Type.body(
                      t.ink,
                      weight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (about case final about?)
                    Text(about, style: Type.note(t.ink)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
