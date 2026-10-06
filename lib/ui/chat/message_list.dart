import 'package:flutter/material.dart';

import '../../core/chat.dart';
import '../../core/server_models.dart';
import '../app_scope.dart';
import '../links.dart';
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
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final workspace = chat.active;
    final turns = chat.turns;
    if (workspace == null) return const SizedBox.shrink();
    if (turns.isEmpty) {
      return _Empty(workspace: workspace.name, onSuggest: onSuggest);
    }
    // The person's text size scales the turns, not the controls around them.
    return ListenableBuilder(
      listenable: scope.prefs,
      builder: (context, _) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: _TimesScaler(
              media.textScaler,
              scope.prefs.prefs.textSize.scale,
            ),
          ),
          child: _turns(turns),
        );
      },
    );
  }

  Widget _turns(List<Turn> turns) {
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
    final sources = AppScope.of(context).sources;
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
              ListenableBuilder(
                listenable: Listenable.merge([sources, sources.chatMode]),
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Text(
                        sources.chatMode.value?.about ?? everyModeDrawsOn,
                        textAlign: TextAlign.center,
                        style: Type.sans(15.5, color: t.muted, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s
                            in sources.files.isEmpty
                                ? const ['What can I do here?']
                                : const [
                                    'Summarise my files',
                                    'What are the key points?',
                                  ])
                          _Suggestion(s, onTap: () => onSuggest(s)),
                      ],
                    ),
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
    final split = splitReasoning(turn.text);
    final thinking = turn.streaming && split.thinking;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thinking || split.reasoning.isNotEmpty) ...[
          _Reasoning(split.reasoning, thinking: thinking),
          if (split.answer.isNotEmpty) const SizedBox(height: 10),
        ],
        if (split.answer.isNotEmpty) AnswerBody(split.answer),
        if (turn.streaming && turn.status != null) _Status(turn.status!),
        if (turn.streaming && !thinking)
          const Padding(padding: EdgeInsets.only(top: 6), child: Caret()),
        if (turn.error case final error?) ...[
          const SizedBox(height: 10),
          AlertBox(AlertKind.bad, 'The answer stopped', text: error),
        ],
        if (!turn.streaming && turn.citations.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Citations(turn.citations),
        ],
        if (!turn.streaming && split.answer.isNotEmpty) ...[
          const SizedBox(height: 6),
          CopyButton(split.answer, tooltip: 'Copy answer'),
        ],
      ],
    );
  }
}

/// What the agent is doing while the answer runs, such as a tool it runs. It goes when the
/// answer is done.
class _Status extends StatelessWidget {
  const _Status(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Type.sans(
            13,
            color: t.muted,
            height: 1.4,
          ).copyWith(fontStyle: FontStyle.italic),
        ),
      ),
    );
  }
}

/// The model's reasoning before its answer, folded away. While the model is still reasoning it
/// says so; afterwards a tap shows or hides what it wrote.
class _Reasoning extends StatefulWidget {
  const _Reasoning(this.text, {required this.thinking});

  final String text;
  final bool thinking;

  @override
  State<_Reasoning> createState() => _ReasoningState();
}

class _ReasoningState extends State<_Reasoning> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final label = widget.thinking
        ? 'Thinking…'
        : _open
        ? 'Hide reasoning'
        : 'Show reasoning';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Tappable(
          label: label,
          onTap: widget.text.isEmpty
              ? null
              : () => setState(() => _open = !_open),
          radius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedRotation(
                  turns: _open ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: AppIcon('chevron', size: IconSize.xs, color: t.muted),
                ),
                const SizedBox(width: 6),
                Text(label, style: Type.sans(13.5, color: t.muted)),
                if (widget.thinking) ...[
                  const SizedBox(width: 8),
                  const Caret(),
                ],
              ],
            ),
          ),
        ),
        if (_open && widget.text.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6, left: 6),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: t.line, width: 2)),
            ),
            child: SelectableText(
              widget.text,
              style: Type.sans(14, color: t.muted, height: 1.55),
            ),
          ),
      ],
    );
  }
}

/// The sources an answer drew on. An agent's can be dozens of web pages, so past the first few
/// they fold behind a count.
class _Citations extends StatefulWidget {
  const _Citations(this.citations);

  final List<Citation> citations;

  static const shown = 5;

  @override
  State<_Citations> createState() => _CitationsState();
}

class _CitationsState extends State<_Citations> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final citations = widget.citations;
    final folded = !_all && citations.length > _Citations.shown + 1;
    final count = folded ? _Citations.shown : citations.length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (i, citation) in citations.take(count).indexed)
          _Citation(number: i + 1, citation: citation),
        if (folded)
          Tappable(
            label: '${citations.length - count} more sources',
            onTap: () => setState(() => _all = true),
            radius: BorderRadius.circular(99),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                '${citations.length - count} more',
                style: Type.sans(12.5, color: t.muted),
              ),
            ),
          ),
      ],
    );
  }
}

/// One source. A file in Sources lights up there when tapped, and a web page an agent read opens
/// in the browser; anything else, such as a file since removed, only shows its title.
class _Citation extends StatelessWidget {
  const _Citation({required this.number, required this.citation});

  final int number;
  final Citation citation;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppScope.of(context).sources,
    builder: _build,
  );

  Widget _build(BuildContext context, Widget? _) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final title = citation.title;
    final url = citation.url;
    final present = scope.sources.byTitle(title) != null;
    final live = present || url != null;
    return Tappable(
      label: present || url == null
          ? 'Source $number: $title'
          : 'Source $number: $title, opens in the browser',
      tooltip: present ? 'Show in Sources' : url?.toString(),
      onTap: present
          ? () {
              scope.shell.openSources();
              scope.sources.flash(title);
            }
          : url == null
          ? null
          : () => openLink(context, url.toString()),
      radius: BorderRadius.circular(99),
      color: live ? t.accentbg : t.hover,
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
                color: live ? t.accent : t.muted,
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
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.sans(12.5, color: live ? t.accent : t.ink2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The system's text scaling, which may be non-linear, times the person's chat text size.
class _TimesScaler extends TextScaler {
  const _TimesScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @Deprecated('Use scale instead.')
  @override
  double get textScaleFactor => scale(14) / 14;

  @override
  bool operator ==(Object other) =>
      other is _TimesScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
