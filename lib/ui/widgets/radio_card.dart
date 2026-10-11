import 'package:flutter/material.dart';

import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// One choice of several: a radio ring, [title], the line [about] under it and [hint] after
/// it. As a [card], it sits in a box filled while chosen; otherwise it is a plain row. A title
/// not chosen is at [restWeight], and a chosen one semibold.
class RadioCard extends StatelessWidget {
  const RadioCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.about,
    this.hint,
    this.card = true,
    this.restWeight = FontWeight.w400,
  });

  final String title;
  final String? about;
  final String? hint;
  final bool selected;
  final bool card;
  final FontWeight restWeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: [title, ?hint, ?about].join('. '),
      selected: selected,
      onTap: onTap,
      radius: BorderRadius.circular(12),
      color: card ? (selected ? t.sel : t.panel) : null,
      side: card
          ? BorderSide(color: selected ? Colors.transparent : t.line)
          : null,
      child: Container(
        constraints: BoxConstraints(minHeight: card ? 56 : 48),
        padding: EdgeInsets.symmetric(
          horizontal: card ? 12 : 0,
          vertical: card ? 8 : 6,
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? t.accent : t.fade,
                  width: 1.5,
                ),
              ),
              child: selected
                  ? Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: t.accent,
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 1,
                children: [
                  Text(
                    title,
                    style: Type.sans(
                      15,
                      weight: selected ? FontWeight.w600 : restWeight,
                      color: t.ink,
                    ),
                  ),
                  if (about case final about?)
                    Text(
                      about,
                      style: Type.sans(12.5, color: t.muted, height: 1.4),
                    ),
                ],
              ),
            ),
            if (hint case final hint?)
              Text(hint, style: Type.sans(12.5, color: t.muted)),
          ],
        ),
      ),
    );
  }
}
