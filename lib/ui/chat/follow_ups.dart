import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/shortcuts.dart';
import '../app_scope.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/tappable.dart';

/// A row of pills under the chat's last answer: the [followUpShortcuts], each sending its
/// shortcut as the next message with no detail, then More, which puts `/` in the message to
/// list every shortcut. It scrolls sideways when it is wider than the chat.
class FollowUps extends StatelessWidget {
  const FollowUps({super.key, required this.onMore});

  /// Called by More.
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final chat = AppScope.of(context).chat;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          spacing: 8,
          children: [
            for (final shortcut in followUpShortcuts)
              _Pill(
                shortcut.label,
                onTap: () => unawaited(
                  chat.send(
                    shortcut.expand(''),
                    shortcutUse: ShortcutUse(label: shortcut.label, detail: ''),
                  ),
                ),
              ),
            _Pill('More', onTap: onMore, label: 'More shortcuts'),
          ],
        ),
      ),
    );
  }
}

/// One follow-up: a pill 44 tall on `panel` inside a `line2` edge.
class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.onTap, this.label});

  final String text;
  final VoidCallback onTap;

  /// What a screen reader hears, when it is not [text].
  final String? label;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: label ?? text,
      onTap: onTap,
      radius: BorderRadius.circular(99),
      color: t.panel,
      side: BorderSide(color: t.line2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            widthFactor: 1,
            child: Text(
              text,
              maxLines: 1,
              style: Type.sans(14.5, color: t.ink2),
            ),
          ),
        ),
      ),
    );
  }
}
