import 'package:flutter/material.dart';

import '../../core/commands.dart';
import '../tokens.dart';
import '../type.dart';
import 'composer_chip.dart';

/// What a screen reader hears for [command]: it and its description.
String _heard(SlashCommand command) => command.description.isEmpty
    ? command.command
    : '${command.command}: ${command.description}';

/// The commands that match what is typed: one line of suggestions over the composer that
/// scrolls sideways, each a [ComposerChip] that puts its command in the message and never takes
/// the field's focus, with [note], when there is one, under them.
class SlashStrip extends StatelessWidget {
  const SlashStrip({
    super.key,
    required this.commands,
    required this.onPick,
    this.note,
  });

  final List<SlashCommand> commands;
  final ValueChanged<SlashCommand> onPick;

  /// Why some commands are missing.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: commands.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = commands[i];
              return Center(
                child: ComposerChip(
                  text: c.command,
                  label: _heard(c),
                  tooltip: c.description.isEmpty ? null : c.description,
                  onTap: () => onPick(c),
                ),
              );
            },
          ),
        ),
        if (note case final note?)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Type.sans(12.5, color: t.muted),
            ),
          ),
      ],
    );
  }
}
