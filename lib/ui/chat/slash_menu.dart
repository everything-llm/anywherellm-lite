import 'package:flutter/material.dart';

import '../../core/commands.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/tappable.dart';

/// What a screen reader hears for [command]: it and its description.
String _heard(SlashCommand command) => command.description.isEmpty
    ? command.command
    : '${command.command}: ${command.description}';

/// The commands that match what is typed: a card over the composer, a row for each, its
/// command in the mono face over its description, that puts its command in the message and
/// never takes the field's focus, with [note], when there is one, under them. Past
/// [maxHeight] it scrolls.
class SlashMenu extends StatelessWidget {
  const SlashMenu({
    super.key,
    required this.commands,
    required this.onPick,
    this.note,
  });

  final List<SlashCommand> commands;
  final ValueChanged<SlashCommand> onPick;

  /// Why some commands are missing.
  final String? note;

  /// The tallest the card stands, room for four commands.
  static const maxHeight = 244.0;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      container: true,
      label: 'Commands',
      explicitChildNodes: true,
      child: Container(
        constraints: const BoxConstraints(maxHeight: maxHeight),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: t.panel,
          borderRadius: BorderRadius.circular(Sizes.phoneCard),
          border: Border.all(color: t.line2),
          boxShadow: [
            BoxShadow(
              color: t.shadow,
              blurRadius: 32,
              spreadRadius: -12,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ExcludeFocus(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              for (final (i, c) in commands.indexed)
                Tappable(
                  label: _heard(c),
                  onTap: () => onPick(c),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 60),
                    decoration: BoxDecoration(
                      border: i == 0
                          ? null
                          : Border(top: BorderSide(color: t.line2)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.command,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.mono(
                            15,
                            weight: FontWeight.w600,
                            color: t.ink,
                          ),
                        ),
                        if (c.description.isNotEmpty)
                          Text(
                            c.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Type.sans(13, color: t.muted),
                          ),
                      ],
                    ),
                  ),
                ),
              if (note case final note?)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.line2)),
                  ),
                  child: Text(
                    note,
                    style: Type.sans(13, color: t.muted, height: 1.45),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
