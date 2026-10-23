import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/server_models.dart';
import '../../core/shortcuts.dart';
import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import 'shortcut_chip.dart';

/// The widest a question's bubble is drawn, as the Lite prototype draws it.
const questionWidth = 300.0;

/// A question's bubble's corners: round but for its bottom right, which points at the edge it
/// sits on.
const questionRadius = BorderRadius.only(
  topLeft: Radius.circular(24),
  topRight: Radius.circular(24),
  bottomLeft: Radius.circular(24),
  bottomRight: Radius.circular(8),
);

/// The room inside a question's bubble around its words.
const questionPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);

/// What a question's bubble holds: its words, or the [shortcutUse] chip and detail in their
/// place, then the files that go with it, a picture drawn small and any other by its name, and
/// the names of [lost] files, which it goes without.
class QuestionBody extends StatelessWidget {
  const QuestionBody(
    this.text, {
    super.key,
    this.attachments = const [],
    this.shortcutUse,
    this.lost = const [],
  });

  final String text;
  final List<SentFile> attachments;

  /// The shortcut to show in place of [text], or null to show [text].
  final ShortcutUse? shortcutUse;
  final List<String> lost;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shortcutUse case final use?) ...[
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              ShortcutChip(use.label),
              if (use.detail.isNotEmpty)
                Text(
                  use.detail,
                  style: Type.sans(Type.chat, color: t.ink, height: 1.5),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Shortcut · the server keeps the full prompt',
            style: Type.note(t.ink),
          ),
        ] else
          Text(text, style: Type.sans(Type.chat, color: t.ink, height: 1.5)),
        for (final file in attachments)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: switch (file.picture) {
              final bytes? => _Picture(bytes, name: file.name),
              null => _FileName(file.name),
            },
          ),
        for (final name in lost)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _FileName('$name · not kept'),
          ),
      ],
    );
  }
}

/// A file sent with a question, by its name.
class _FileName extends StatelessWidget {
  const _FileName(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon('attach', size: IconSize.xs, color: t.ink),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Type.note(t.ink),
          ),
        ),
      ],
    );
  }
}

/// A picture sent with a question, drawn small; its name when its bytes do not decode.
class _Picture extends StatelessWidget {
  const _Picture(this.bytes, {required this.name});

  final Uint8List bytes;
  final String name;

  static const _height = 120.0;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: _height, maxWidth: 240),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        bytes,
        fit: BoxFit.contain,
        cacheHeight: (_height * MediaQuery.devicePixelRatioOf(context)).round(),
        semanticLabel: name,
        errorBuilder: (_, _, _) => _FileName(name),
      ),
    ),
  );
}
