import 'package:flutter/material.dart';

import '../../core/commands.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/tappable.dart';
import 'composer_chip.dart';

/// The commands that match what is typed, shown above the message while it starts with a slash.
/// The [highlight]ed one is what Enter or Tab picks. A phone shows [SlashStrip] instead.
class SlashMenu extends StatelessWidget {
  const SlashMenu({
    super.key,
    required this.commands,
    required this.highlight,
    required this.onPick,
    this.note,
  });

  final List<SlashCommand> commands;

  /// Why some commands are missing, shown under them.
  final String? note;
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
              label: _heard(c),
              onTap: () => onPick(c),
              selected: i == highlight,
              color: i == highlight ? t.sel : null,
              radius: BorderRadius.circular(8),
              child: _OneLine(c),
            ),
          if (note case final note?)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Text(note, style: Type.sans(12.5, color: t.muted)),
            ),
        ],
      ),
    );
  }
}

/// What a screen reader hears for [command]: it and its description.
String _heard(SlashCommand command) => command.description.isEmpty
    ? command.command
    : '${command.command}: ${command.description}';

/// A phone's commands that match what is typed: one line of suggestions over the composer that
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

/// A command and its description side by side.
class _OneLine extends StatelessWidget {
  const _OneLine(this.command);

  final SlashCommand command;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Flexible(
            flex: 2,
            child: Text(
              command.command,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.mono(13.5, color: t.ink),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            flex: 3,
            child: Text(
              command.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Type.sans(13, color: t.muted),
            ),
          ),
        ],
      ),
    );
  }
}
