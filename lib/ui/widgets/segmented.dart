import 'package:flutter/material.dart';

import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// A row of equal segments on a [Tokens.sunken] track, one of them chosen: the chosen one a tile
/// inside a [Tokens.lineStrong] ring, its label at 600. [onChanged] null shows it disabled. Each
/// segment is drawn at least 44 tall and tapped in a finger's [Tappable.touchSide], which
/// reaches into the track's edge, its label [Type.body].
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  /// Each choice with its label.
  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final onChanged = this.onChanged;
    final enabled = onChanged != null;
    // Disabled it stays opaque: its labels muted, the chosen segment sunken inside a line.
    return Container(
      // 3 round the segments; 2 of it above and below is their hit area.
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: BorderRadius.circular(Sizes.control),
      ),
      child: Row(
        spacing: 8,
        children: [
          for (final (option, label) in options)
            Expanded(
              child: Tappable(
                touchTarget: true,
                label: label,
                selected: value == option,
                onTap: onChanged == null ? null : () => onChanged(option),
                radius: BorderRadius.circular(Sizes.small),
                color: value == option ? (enabled ? t.tile : t.sunken) : null,
                side: value == option
                    ? BorderSide(
                        color: enabled ? t.lineStrong : t.line,
                        width: 1.5,
                      )
                    : null,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.body(
                      enabled ? t.ink : t.muted,
                      weight: value == option
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
