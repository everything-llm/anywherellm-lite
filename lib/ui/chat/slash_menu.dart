import 'package:flutter/material.dart';

import '../../core/commands.dart';
import '../layout.dart';
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
    // A phone's menu is a card of its own over the chat, each command over its description.
    final phone = ScreenClass.ofContext(context).isPhone;
    final list = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: phone ? 260 : 200),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final (i, c) in commands.indexed) ...[
            if (phone && i > 0)
              Divider(height: 1, thickness: 1, color: t.line2),
            Tappable(
              label: c.description.isEmpty
                  ? c.command
                  : '${c.command}: ${c.description}',
              onTap: () => onPick(c),
              selected: i == highlight,
              color: i == highlight && !phone ? t.sel : null,
              radius: BorderRadius.circular(8),
              child: phone ? _TwoLines(c) : _OneLine(c),
            ),
          ],
          if (note case final note?)
            Padding(
              padding: phone
                  ? const EdgeInsets.only(top: 6, bottom: 12)
                  : const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Text(note, style: Type.sans(12.5, color: t.muted)),
            ),
        ],
      ),
    );
    if (!phone) return list;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: t.panel,
        border: Border.all(color: t.line2),
        borderRadius: BorderRadius.circular(Sizes.phoneCard),
        boxShadow: [
          BoxShadow(
            color: t.shadow,
            blurRadius: 26,
            spreadRadius: -12,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: list,
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

/// A command over its description, as a phone's menu lists them.
class _TwoLines extends StatelessWidget {
  const _TwoLines(this.command);

  final SlashCommand command;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            command.command,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Type.mono(15, weight: FontWeight.w600, color: t.ink),
          ),
          if (command.description.isNotEmpty)
            Text(
              command.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Type.sans(13, color: t.muted, height: 1.35),
            ),
        ],
      ),
    );
  }
}
