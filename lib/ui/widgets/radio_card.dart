import 'package:flutter/material.dart';

import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// One choice of several: a radio ring, [title] and the line [about] under it, in a box filled
/// while chosen. A title not chosen is medium, and a chosen one semibold.
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
      radius: BorderRadius.circular(20),
      color: selected ? t.sel : t.panel,
      side: BorderSide(color: selected ? t.sel : t.edge),
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
                spacing: 1,
                children: [
                  Text(
                    title,
                    style: Type.sans(
                      15,
                      weight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: t.ink,
                    ),
                  ),
                  if (about case final about?)
                    Text(
                      about,
                      style: Type.sans(13, color: t.muted, height: 1.4),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
