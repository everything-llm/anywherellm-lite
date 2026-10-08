import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/chat.dart';
import '../../core/outputs.dart';
import '../../core/prefs.dart';
import '../../core/server_models.dart';
import '../app_scope.dart';
import '../links.dart';
import '../icons.dart';
import '../layout.dart';
import '../state/chat_controller.dart';
import '../state/prefs_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/rise.dart';
import '../widgets/tappable.dart';
import 'answer_body.dart';
import 'browser_chip.dart';
import 'generated_files.dart';
import 'speaker.dart';

/// The chat on screen, newest at the bottom. Empty, it invites a first question.
///
/// The list is reversed so it starts at the newest turn and stays pinned there as an answer
/// grows, and builds only the turns in view. Scrolled up from the newest text, what is in view
/// stays put while the answer grows below it. Its parent rebuilds it when the chat changes; a
/// streaming answer rebuilds only itself. Another chat opens at its newest turn, and a message
/// sent scrolls there.
class MessageList extends StatefulWidget {
  const MessageList({super.key, required this.onSuggest});

  /// Puts a suggested question in the composer.
  final ValueChanged<String> onSuggest;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final _scroll = ScrollController();

  /// [ChatController.sends] when the list was last built.
  int? _sends;

  /// How far from the newest text the list may sit and still count as at the bottom.
  static const _atBottom = 8.0;

  /// The newest turn's height as last laid out.
  final _newest = _Extent();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Whether the newest turn's growth should leave what is in view put rather than push it up:
  /// always while the list is scrolled up from the newest text, and while an answer streams
  /// with [ChatSwitch.followAnswer] off. The list is reversed, so its offset counts up from the
  /// newest text.
  bool _holds(Turn? newest, PrefsController prefs) {
    if (_scroll.hasClients && _scroll.position.pixels > _atBottom) return true;
    return newest != null &&
        newest.streaming &&
        !prefs.prefs.isOn(ChatSwitch.followAnswer);
  }

  /// Scrolls to the newest turn after this frame when a message was sent since the last build.
  void _follow(ChatController chat) {
    final sent = _sends != null && chat.sends != _sends;
    _sends = chat.sends;
    if (!sent) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients || _scroll.offset == 0) return;
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final workspace = chat.active;
    final turns = chat.turns;
    if (workspace == null) return const SizedBox.shrink();
    _follow(chat);
    if (turns.isEmpty) {
      return _Empty(workspace: workspace.name, onSuggest: widget.onSuggest);
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
          child: _turns(context, turns),
        );
      },
    );
  }

  /// The key of [turn]'s place in the list, which goes with it as turns are added below it, so
  /// what it shows open or folded stays with it.
  static GlobalObjectKey _keyOf(Turn turn) => GlobalObjectKey(turn);

  Widget _turns(BuildContext context, List<Turn> turns) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    return CustomScrollView(
      // Another chat gets a list of its own, which starts at its newest turn.
      key: ValueKey((chat.activeSlug, chat.activeThread)),
      controller: _scroll,
      reverse: true,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          sliver: _HoldPlace(
            newest: _newest,
            holds: () => _holds(turns.lastOrNull, scope.prefs),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _turn(chat, turns, i),
                childCount: turns.length,
                findChildIndexCallback: (key) {
                  if (key is! GlobalObjectKey) return null;
                  final at = turns.indexWhere((t) => identical(t, key.value));
                  return at < 0 ? null : turns.length - 1 - at;
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The [i]th turn from the newest.
  Widget _turn(ChatController chat, List<Turn> turns, int i) {
    final turn = turns[turns.length - 1 - i];
    final first = i == turns.length - 1;
    // An answer sits closer to its own question than a question to the answer before it.
    final answering =
        !first &&
        turn.role != Role.user &&
        turns[turns.length - 2 - i].role == Role.user;
    return _Measured(
      key: _keyOf(turn),
      into: i == 0 ? _newest : null,
      turn: turn,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Sizes.column),
          child: Padding(
            padding: EdgeInsets.only(
              top: first
                  ? 0
                  : answering
                  ? 16
                  : 26,
            ),
            child: Rise(
              child: turn.role == Role.user
                  ? _UserBubble(
                      turn.text,
                      attachments: turn.attachments,
                      onEdit: () {
                        chat.edit(turn);
                        widget.onSuggest(turn.text);
                      },
                    )
                  : _Answer(turn, retry: i == 0 ? _retryOf(chat) : null),
            ),
          ),
        ),
      ),
    );
  }
}

/// A turn's height as it was last laid out, written by [_Measured] during its own layout,
/// where reading it is allowed.
class _Extent {
  Turn? turn;
  double height = 0;

  /// Whether the turn was laid out since [_RenderHoldPlace] last looked.
  bool fresh = false;
}

/// [child], which writes its height into [into] each time it is laid out.
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({
    super.key,
    required this.into,
    required this.turn,
    required Widget super.child,
  });

  final _Extent? into;
  final Turn turn;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasured(into, turn);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasured renderObject) =>
      renderObject
        ..into = into
        ..turn = turn;
}

class _RenderMeasured extends RenderProxyBox {
  _RenderMeasured(this.into, this.turn);

  _Extent? into;
  Turn turn;

  @override
  void performLayout() {
    super.performLayout();
    if (into case final extent?) {
      extent
        ..turn = turn
        ..height = size.height
        ..fresh = true;
    }
  }
}

/// The turns' list, which keeps what is in view put when the newest turn grows while [holds]:
/// in the same layout, it moves the scroll offset by as much as that turn grew, so nothing that
/// was drawn moves.
class _HoldPlace extends SingleChildRenderObjectWidget {
  const _HoldPlace({
    required this.newest,
    required this.holds,
    required Widget sliver,
  }) : super(child: sliver);

  final _Extent newest;
  final bool Function() holds;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHoldPlace(newest, holds);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHoldPlace renderObject,
  ) => renderObject
    ..newest = newest
    ..holds = holds;
}

class _RenderHoldPlace extends RenderProxySliver {
  _RenderHoldPlace(this.newest, this.holds);

  _Extent newest;
  bool Function() holds;

  /// The newest turn and its height at the last layout that laid it out.
  Turn? _turn;
  double _height = 0;

  @override
  void performLayout() {
    newest.fresh = false;
    super.performLayout();
    final list = child;
    final first = list is RenderSliverMultiBoxAdaptor ? list.firstChild : null;
    if (list is! RenderSliverMultiBoxAdaptor ||
        first == null ||
        list.indexOf(first) != 0) {
      // Out of view: laid out afresh when it comes back, the list places it itself.
      _turn = null;
      return;
    }
    // Laid out before and not since, it has not changed.
    if (!newest.fresh) return;
    // A turn just added below the others is not growth either.
    final grown = identical(newest.turn, _turn) ? newest.height - _height : 0.0;
    _turn = newest.turn;
    _height = newest.height;
    if (grown > 0.5 && holds()) {
      geometry = SliverGeometry(scrollOffsetCorrection: grown);
    }
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

/// Retry on the chat's last answer: [onPressed] is null while it cannot run, and [tooltip]
/// says why when the question went with files.
typedef _Retry = ({VoidCallback? onPressed, String tooltip});

_Retry _retryOf(ChatController chat) {
  final turns = chat.turns;
  final files =
      turns.length >= 2 && turns[turns.length - 2].attachments.isNotEmpty;
  return (
    onPressed: chat.canRetry ? chat.retry : null,
    tooltip: files
        ? 'Retry is off: the files sent with the question are not kept'
        : 'Retry',
  );
}

class _UserBubble extends StatelessWidget {
  const _UserBubble(
    this.text, {
    this.attachments = const [],
    required this.onEdit,
  });

  final String text;

  /// The files sent with the question: a picture drawn small, any other by its name.
  final List<SentFile> attachments;

  /// Puts [text] back in the composer, to replace the question when the app is signed in.
  final VoidCallback onEdit;

  /// Edit sits beside the bubble, at its foot, so nothing stands between it and the answer.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        IconBtn(
          'pencil',
          tooltip: 'Edit',
          onPressed: onEdit,
          box: 28,
          size: IconSize.xs,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.8),
            child: _bubble(context),
          ),
        ),
      ],
    ),
  );

  Widget _bubble(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
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
          for (final file in attachments)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: switch (file.picture) {
                final bytes? => _Picture(bytes, name: file.name),
                null => _FileName(file.name),
              },
            ),
        ],
      ),
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

class _Answer extends StatelessWidget {
  const _Answer(this.turn, {this.retry});

  final Turn turn;

  /// Retry, on the chat's last answer only.
  final _Retry? retry;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: turn, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final split = splitReasoning(turn.text, streaming: turn.streaming);
    final thinking = turn.streaming && split.thinking;
    final failure = turn.streaming ? null : modelFailure(split.answer);
    final answered = split.answer.isNotEmpty && failure == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thinking || split.reasoning.isNotEmpty) ...[
          _Reasoning(split.reasoning, thinking: thinking),
          if (split.answer.isNotEmpty) const SizedBox(height: 10),
        ],
        if (failure != null)
          AlertBox(AlertKind.bad, 'The model did not answer', text: failure)
        else if (split.answer.isNotEmpty)
          AnswerBody(
            split.answer,
            label: AppScope.of(context).labelAnswers && !turn.streaming,
          ),
        if (turn.browsing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: BrowserChip(turn),
          )
        else if (turn.streaming && turn.status != null)
          _Status(turn.status!),
        if (turn.streaming && !thinking)
          const Padding(padding: EdgeInsets.only(top: 6), child: Caret()),
        if (turn.error case final error?) ...[
          const SizedBox(height: 10),
          if (turn.stillRunning)
            const StatusBox(
              'Still being written',
              text:
                  'The connection dropped, but the answer keeps going on the server. It will '
                  'appear here when it\'s done; Refresh checks for it sooner.',
            )
          else
            AlertBox(AlertKind.bad, 'The answer stopped', text: error),
        ],
        if (!turn.streaming &&
            turn.browserSteps.isNotEmpty &&
            AppScope.of(context).chat.cardsOf(turn).isEmpty) ...[
          const SizedBox(height: 10),
          BrowserChip(turn),
        ],
        if (!turn.streaming && turn.citations.isNotEmpty) ...[
          const SizedBox(height: 12),
          _Citations(turn.citations),
        ],
        if (!turn.streaming && turn.files.isNotEmpty) ...[
          const SizedBox(height: 12),
          GeneratedFiles(turn.files),
        ],
        if (!turn.streaming && (answered || retry != null)) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (answered) CopyButton(split.answer, tooltip: 'Copy answer'),
              if (AppScope.of(context).readAloud case final aloud?
                  when answered)
                _ReadAloudButton(aloud, turn),
              if (retry case final retry?)
                IconBtn(
                  'refresh',
                  tooltip: retry.tooltip,
                  onPressed: retry.onPressed,
                  box: 30,
                  size: IconSize.xs,
                ),
              if (_feedbackOf(context, turn) case final chat?
                  when answered) ...[
                for (final good in const [true, false])
                  IconBtn(
                    good ? 'thumb-up' : 'thumb-down',
                    tooltip: good ? 'Good answer' : 'Bad answer',
                    active: turn.feedback == good,
                    onPressed: () => chat.mark(turn, good),
                    box: 30,
                    size: IconSize.xs,
                  ),
              ],
              if (turn.metrics case final metrics?) _Metrics(metrics),
            ],
          ),
        ],
      ],
    );
  }
}

/// How an answer ran: the model and the time, and Details for the rest when there is more.
class _Metrics extends StatefulWidget {
  const _Metrics(this.metrics);

  final AnswerMetrics metrics;

  @override
  State<_Metrics> createState() => _MetricsState();
}

class _MetricsState extends State<_Metrics> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final metrics = widget.metrics;
    final more = metrics.hasMore;
    final shown = _open || !more ? metrics.text : metrics.brief;
    final style = Type.sans(12, color: t.muted);
    const hide = 'Hide details';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shown.isNotEmpty) Flexible(child: Text(shown, style: style)),
        if (more)
          Tappable(
            label: _open ? hide : 'Answer details: tokens, speed and cost',
            expanded: _open,
            onTap: () => setState(() => _open = !_open),
            radius: BorderRadius.circular(6),
            child: Container(
              height: 30,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                _open ? hide : 'Details',
                style: style.copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: t.muted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The chat that can mark [turn] good or bad, or null when it cannot: the app is not signed in
/// to the server, or the server has not said the answer's id.
ChatController? _feedbackOf(BuildContext context, Turn turn) {
  final chat = AppScope.of(context).chat;
  return chat.signedIn && turn.chatId != null ? chat : null;
}

/// Reads [turn] aloud, or stops it while it is being read.
class _ReadAloudButton extends StatelessWidget {
  const _ReadAloudButton(this.aloud, this.turn);

  final ReadAloud aloud;
  final Turn turn;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: aloud,
    builder: (context, _) {
      final reading = identical(aloud.reading, turn);
      return IconBtn(
        reading ? 'stop' : 'speaker',
        tooltip: reading ? 'Stop reading' : 'Read aloud',
        onPressed: () => aloud.toggle(turn),
        box: 30,
        size: IconSize.xs,
      );
    },
  );
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
  late bool _open = AppScope.of(context).prefs.prefs
      .isOn(ChatSwitch.reasoningOpen);

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
