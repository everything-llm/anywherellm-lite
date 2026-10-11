import 'package:flutter/material.dart';

import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// A row of equal segments, one of them chosen. [onChanged] null shows it disabled. On a phone
/// each segment is at least 40 tall, its label at 14.5, as the design canvas draws it.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
  });

  /// The lines a label may wrap to before it is cut short. Above one, every segment is as tall
  /// as the tallest.
  final int maxLines;

  /// Each choice with its label.
  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T>? onChanged;

  /// The [segments] side by side at equal widths, each as tall as the tallest when labels wrap.
  Widget _rows(List<Widget> segments) {
    final row = Row(
      crossAxisAlignment: maxLines > 1
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
      children: [for (final s in segments) Expanded(child: s)],
    );
    return maxLines > 1 ? IntrinsicHeight(child: row) : row;
  }

  /// [label] in the middle of its segment when labels wrap, so a shorter one sits level.
  Widget _centred(Widget label) => maxLines > 1 ? Center(child: label) : label;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final onChanged = this.onChanged;
    final phone = ScreenClass.ofContext(context).isPhone;
    return Opacity(
      opacity: onChanged == null ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: t.hover,
          borderRadius: BorderRadius.circular(phone ? 12 : 10),
        ),
        child: _rows([
          for (final (option, label) in options)
            Tappable(
              label: label,
              selected: value == option,
              onTap: onChanged == null ? null : () => onChanged(option),
              radius: BorderRadius.circular(phone ? 9 : 8),
              color: value == option ? t.panel : null,
              child: _centred(
                Container(
                  constraints: BoxConstraints(minHeight: phone ? 40 : 0),
                  alignment: phone ? Alignment.center : null,
                  padding: EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: maxLines > 1 ? 4 : 0,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(
                      phone ? 14.5 : 13.5,
                      weight: value == option
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: t.ink,
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
