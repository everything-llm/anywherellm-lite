import 'package:flutter/material.dart';

import '../../core/commands.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/tappable.dart';

/// The commands that match what is typed, shown above the message while it starts with a slash.
/// The [highlight]ed one is what Enter or Tab picks.
class SlashMenu extends StatelessWidget {
  const SlashMenu({
    super.key,
    required this.commands,
    required this.highlight,
    required this.onPick,
  });

  final List<SlashCommand> commands;
  final int highlight;
  final ValueChanged<SlashCommand> onPick;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final (i, c) in commands.indexed)
            Tappable(
              label: c.description.isEmpty
                  ? c.command
                  : '${c.command}: ${c.description}',
              onTap: () => onPick(c),
              selected: i == highlight,
              color: i == highlight ? t.sel : null,
              radius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      flex: 2,
                      child: Text(
                        c.command,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.mono(13.5, color: t.ink),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      flex: 3,
                      child: Text(
                        c.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.sans(13, color: t.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
