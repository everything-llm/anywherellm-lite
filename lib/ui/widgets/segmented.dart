import 'package:flutter/material.dart';

import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// A row of equal segments, one of them chosen. [onChanged] null shows it disabled.
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
    return Opacity(
      opacity: onChanged == null ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: t.hover,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            for (final (option, label) in options)
              Expanded(
                child: Tappable(
                  label: label,
                  selected: value == option,
                  onTap: onChanged == null ? null : () => onChanged(option),
                  radius: BorderRadius.circular(8),
                  color: value == option ? t.panel : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.sans(
                        13.5,
                        weight: value == option
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: t.ink,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
