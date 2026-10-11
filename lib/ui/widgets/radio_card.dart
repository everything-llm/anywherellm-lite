import 'package:flutter/material.dart';

import '../layout.dart';
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
    // A phone's card is roomier and rounder, rings itself in the selection colour when chosen,
    // and marks the choice with a thick ring rather than a dot, as the design canvas draws it.
    final phone = ScreenClass.ofContext(context).isPhone;
    return Tappable(
      label: [title, ?hint, ?about].join('. '),
      selected: selected,
      onTap: onTap,
      radius: BorderRadius.circular(phone ? 20 : 12),
      color: card ? (selected ? t.sel : t.panel) : null,
      side: card
          ? BorderSide(
              color: selected ? (phone ? t.sel : Colors.transparent) : t.line,
            )
          : null,
      child: Container(
        constraints: BoxConstraints(minHeight: card ? (phone ? 64 : 56) : 48),
        padding: EdgeInsets.symmetric(
          horizontal: card ? (phone ? 18 : 12) : 0,
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
                  color: selected
                      ? t.accent
                      : phone
                      ? t.muted
                      : t.fade,
                  width: selected && phone ? 5 : 1.5,
                ),
              ),
              child: selected && !phone
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
                      weight: selected
                          ? FontWeight.w600
                          : phone
                          ? FontWeight.w500
                          : restWeight,
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
