import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// A row of a wide window's list, as the sidebar and a list beside what it opens draw it: an
/// optional [icon] or [lead], [title] with [about] under it, a [note] at its end, then
/// [trailing] apart from the row's tap, such as a switch or More. While [selected] it has a
/// filled ground, a bar in the accent at its start and its title in bold, and a screen reader
/// hears it as the one chosen.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    required this.onTap,
    this.icon,
    this.lead,
    this.about,
    this.aboutSpan,
    this.aboutLines = 1,
    this.note,
    this.selected = false,
    this.heard,
    this.badges = const [],
    this.trailing,
  });

  /// The least height of a row, as a finger needs.
  static const height = 56.0;

  /// A row's corners.
  static const radius = 12.0;

  final String title;
  final VoidCallback? onTap;

  /// An icon before [title].
  final String? icon;

  /// What stands before [title] in place of an [icon], such as a document's type.
  final Widget? lead;

  /// The line under [title].
  final String? about;

  /// The line under [title] drawn as it says, in place of [about], which a screen reader still
  /// hears through [heard].
  final InlineSpan? aboutSpan;

  /// How many lines [about] may take before it is cut short.
  final int aboutLines;

  /// What the row ends in, small and muted, such as how many there are.
  final String? note;
  final bool selected;

  /// What a screen reader hears, when it says more than [title], [about] and [note].
  final String? heard;

  /// Small marks after [title], such as a chat's pin.
  final List<Widget> badges;

  /// A control at the row's end with a tap of its own.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final row = Tappable(
      label: heard ?? [title, ?about, ?note].join(', '),
      selected: selected,
      onTap: onTap,
      radius: BorderRadius.circular(radius),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: height),
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 8, trailing == null ? 12 : 4, 8),
          child: Row(
            spacing: 12,
            children: [
              if (lead case final lead?)
                lead
              else if (icon case final icon?)
                AppIcon(icon, color: t.ink),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      spacing: 6,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: Type.body(
                              t.ink,
                              weight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        ...badges,
                      ],
                    ),
                    if (aboutSpan case final span?)
                      Text.rich(
                        span,
                        maxLines: aboutLines,
                        overflow: TextOverflow.ellipsis,
                        style: Type.note(t.ink),
                      )
                    else if (about case final about? when about.isNotEmpty)
                      Text(
                        about,
                        maxLines: aboutLines,
                        overflow: TextOverflow.ellipsis,
                        style: Type.note(t.ink),
                      ),
                  ],
                ),
              ),
              if (note case final note? when note.isNotEmpty)
                Text(note, style: Type.note(t.ink)),
            ],
          ),
        ),
      ),
    );
    final line = Row(
      children: [
        Expanded(child: row),
        ?trailing,
      ],
    );
    if (!selected) return line;
    // Only the chosen row is filled, and clipped to its corners for the bar at its start.
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.accentSoft,
          border: BorderDirectional(
            start: BorderSide(color: t.accent, width: 4),
          ),
        ),
        child: line,
      ),
    );
  }
}
