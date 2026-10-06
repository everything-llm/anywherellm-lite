import 'package:flutter/material.dart';

import '../../core/server_models.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../state/chat_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/controls.dart';
import '../widgets/rise.dart';
import '../widgets/tappable.dart';
import 'answer_body.dart';

/// The chat on screen, newest at the bottom. Empty, it invites a first question.
///
/// The list is reversed so it starts at the newest turn and stays pinned there as an answer
/// grows, and builds only the turns in view. Its parent rebuilds it when the chat changes; a
/// streaming answer rebuilds only itself.
class MessageList extends StatelessWidget {
  const MessageList({super.key, required this.onSuggest});

  /// Puts a suggested question in the composer.
  final ValueChanged<String> onSuggest;

  @override
  Widget build(BuildContext context) {
    final chat = AppScope.of(context).chat;
    final workspace = chat.active;
    final turns = chat.turns;
    if (workspace == null) return const SizedBox.shrink();
    if (turns.isEmpty) {
      return _Empty(workspace: workspace.name, onSuggest: onSuggest);
    }
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      itemCount: turns.length,
      itemBuilder: (context, i) {
        final turn = turns[turns.length - 1 - i];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Sizes.column),
            child: Padding(
              padding: EdgeInsets.only(top: i == turns.length - 1 ? 0 : 26),
              child: Rise(
                child: turn.role == Role.user
                    ? _UserBubble(turn.text, attachments: turn.attachments)
                    : _Answer(turn),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.workspace, required this.onSuggest});

  final String workspace;
  final ValueChanged<String> onSuggest;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final headline = Type.serif(
      40,
      color: t.ink,
      height: 1.1,
      letterSpacing: -0.6,
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Rise(
          duration: const Duration(milliseconds: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Text.rich(
                  TextSpan(
                    style: headline,
                    children: [
                      const TextSpan(text: 'Ask anything about what’s in '),
                      TextSpan(
                        text: workspace,
                        style: headline.copyWith(fontStyle: FontStyle.italic),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  'Answers come from the files you’ve switched on in Sources.',
                  textAlign: TextAlign.center,
                  style: Type.sans(15.5, color: t.muted, height: 1.5),
                ),
              ),
              const SizedBox(height: 22),
              ListenableBuilder(
                listenable: AppScope.of(context).sources,
                builder: (context, _) => Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s
                        in AppScope.of(context).sources.files.isEmpty
                            ? const ['What can I do here?']
                            : const [
                                'Summarise my files',
                                'What are the key points?',
                              ])
                      _Suggestion(s, onTap: () => onSuggest(s)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Suggestion extends StatefulWidget {
  const _Suggestion(this.text, {required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  State<_Suggestion> createState() => _SuggestionState();
}

class _SuggestionState extends State<_Suggestion> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final lit = _hover ? t.accent : null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tappable(
        label: widget.text,
        onTap: widget.onTap,
        radius: BorderRadius.circular(99),
        color: t.panel,
        side: BorderSide(color: lit ?? t.line),
        hoverColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(widget.text, style: Type.sans(14, color: lit ?? t.ink)),
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble(this.text, {this.attachments = const []});

  final String text;

  /// The names of the files sent with the question.
  final List<String> attachments;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
        widthFactor: 0.8,
        alignment: Alignment.centerRight,
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: t.bubble,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(Sizes.card),
                topRight: Radius.circular(Sizes.card),
                bottomLeft: Radius.circular(Sizes.card),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: Type.sans(15.5, color: t.ink, height: 1.5)),
                for (final name in attachments)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon('attach', size: IconSize.xs, color: t.muted),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Type.sans(13, color: t.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer(this.turn);

  final Turn turn;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: turn, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (turn.text.isNotEmpty) AnswerBody(turn.text),
        if (turn.streaming)
          const Padding(padding: EdgeInsets.only(top: 6), child: Caret()),
        if (turn.error case final error?) ...[
          const SizedBox(height: 10),
          AlertBox(AlertKind.bad, 'The answer stopped', text: error),
        ],
        if (!turn.streaming && turn.citations.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (i, title) in turn.citations.indexed)
                _Citation(number: i + 1, title: title),
            ],
          ),
        ],
        if (!turn.streaming && turn.text.isNotEmpty) ...[
          const SizedBox(height: 6),
          CopyButton(turn.text, tooltip: 'Copy answer'),
        ],
      ],
    );
  }
}

/// A numbered chip naming a document the answer drew on. Tapping it shows the file in Sources.
class _Citation extends StatelessWidget {
  const _Citation({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppScope.of(context).sources,
    builder: _build,
  );

  Widget _build(BuildContext context, Widget? _) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final present = scope.sources.byTitle(title) != null;
    final name = present ? title : 'Removed file';
    return Tappable(
      label: 'Source $number: $name',
      tooltip: present ? 'Show in Sources' : null,
      onTap: present
          ? () {
              scope.shell.openSources();
              scope.sources.flash(title);
            }
          : null,
      radius: BorderRadius.circular(99),
      color: t.accentbg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.accent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$number',
                style: Type.sans(
                  10,
                  weight: FontWeight.w600,
                  color: t.onaccent,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.sans(12.5, color: t.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
