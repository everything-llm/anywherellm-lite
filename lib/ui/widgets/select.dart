import 'package:flutter/material.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';

/// One choice in a [NilsSelect].
typedef SelectOption = ({String value, String label});

/// A closed control that opens a menu of [options]: 44px tall, like [NilsField], showing the
/// current choice. [label] is what a screen reader hears before the choice.
class NilsSelect extends StatelessWidget {
  const NilsSelect({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<SelectOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final current = options.firstWhere(
      (option) => option.value == value,
      orElse: () => options.first,
    );
    return Semantics(
      label: '$label, ${current.label}',
      button: true,
      excludeSemantics: true,
      child: PopupMenuButton<String>(
        tooltip: label,
        initialValue: value,
        onSelected: onChanged,
        color: t.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Sizes.control),
          side: BorderSide(color: t.line),
        ),
        position: PopupMenuPosition.under,
        itemBuilder: (context) => [
          for (final option in options)
            PopupMenuItem(
              value: option.value,
              child: Text(
                option.label,
                style: Type.sans(
                  14.5,
                  weight: option.value == value
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: t.ink,
                ),
              ),
            ),
        ],
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: BorderRadius.circular(Sizes.control),
            border: Border.all(color: t.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  current.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(14.5, color: t.ink),
                ),
              ),
              const SizedBox(width: 8),
              NilsIcon(
                'chevron',
                size: IconSize.sm,
                color: t.muted,
                rotated: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
