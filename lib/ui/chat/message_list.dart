import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/chat.dart';
import '../../core/prefs.dart';
import '../../core/server_models.dart';
import '../../core/sources.dart';
import '../app_scope.dart';
import '../links.dart';
import '../icons.dart';
import '../layout.dart';
import '../state/chat_controller.dart';
import '../state/prefs_controller.dart';
import '../state/shell_controller.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/headline.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/pull_refresh.dart';
import '../widgets/rise.dart';
import '../widgets/sheet.dart';
import '../widgets/tappable.dart';
import 'answer_body.dart';
import 'markdown_lists.dart';
import 'answer_menu.dart';
import 'app_panel.dart';
import 'approval_card.dart';
import 'browser_chip.dart';
import 'generated_files.dart';
import 'passages_sheet.dart';
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

  /// On a phone with a web view, starts loading the page of the chat's newest app card after
  /// this frame, so the card's sheet opens on the page at once.
  void _prefetchApp(BuildContext context, AppScope scope) {
    final view = scope.appView;
    if (view == null || !ScreenClass.ofContext(context).isPhone) return;
    final app = scope.chat.appCard;
    if (app == null) return;
    final page = appPageOf(context, app);
    WidgetsBinding.instance.addPostFrameCallback((_) => view.prefetch(page));
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final workspace = chat.active;
    final turns = chat.turns;
    if (workspace == null) return const SizedBox.shrink();
    _follow(chat);
    _prefetchApp(context, scope);
    if (turns.isEmpty) {
      return _Empty(workspace: workspace.name, onSuggest: widget.onSuggest);
    }
    // The person's text size scales the turns, not the controls around them. The turns are
    // built once here: a change to another pref, such as a pin, leaves the scale as it was, so
    // MediaQuery tells them nothing.
    return ListenableBuilder(
      listenable: scope.prefs,
      child: _turns(context, turns),
      builder: (context, turns) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: _TimesScaler(
              media.textScaler,
              scope.prefs.prefs.textSize.scale,
            ),
          ),
          child: turns!,
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
    // On a phone a pull down past the oldest turn reads the chat again, in place of the
    // header's Refresh.
    final phone = ScreenClass.ofContext(context).isPhone;
    // The list is reversed, so a long chat opens at its newest turn; it is as tall as its turns
    // and sits at the top, so a short chat starts under the header, as the design canvas
    // draws it.
    final list = CustomScrollView(
      // Another chat gets a list of its own, which starts at its newest turn.
      key: ValueKey((chat.activeSlug, chat.activeThread)),
      controller: _scroll,
      reverse: true,
      shrinkWrap: true,
      physics: phone ? const AlwaysScrollableScrollPhysics() : null,
      slivers: [
        SliverPadding(
          padding: phone
              ? const EdgeInsets.fromLTRB(16, 16, 16, 12)
              : const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
    final top = Align(alignment: Alignment.topCenter, child: list);
    if (!phone) return top;
    // MessageList is built afresh as the chat changes, so this follows refreshing.
    return PullRefresh(
      refreshing: chat.refreshing,
      onRefresh: chat.refresh,
      child: top,
    );
  }

  /// The [i]th turn from the newest.
  Widget _turn(ChatController chat, List<Turn> turns, int i) {
    final turn = turns[turns.length - 1 - i];
    final first = i == turns.length - 1;
    // An answer sits closer to its own question than a question to the answer before it. On a
    // phone every turn is 14 from the one before.
    final answering =
        !first &&
        turn.role != Role.user &&
        turns[turns.length - 2 - i].role == Role.user;
    final phone = ScreenClass.ofContext(context).isPhone;
    return _Measured(
      key: _keyOf(turn),
      into: i == 0 ? _newest : null,
      turn: turn,
      child: Center(
        // The column's full width, or the chat's where that is narrower, so a short answer
        // starts at its left edge rather than shrinking to its text and sitting in the middle.
        child: SizedBox(
          width: Sizes.column,
          child: Padding(
            padding: EdgeInsets.only(
              top: first
                  ? 0
                  : phone
                  ? 14
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
                  : _Answer(
                      turn,
                      last: i == 0,
                      retry: i == 0 ? _retryOf(chat) : null,
                    ),
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
    final sources = AppScope.of(context).sources;
    // A phone stacks the suggestions under the headline, as the design canvas draws them.
    final phone = ScreenClass.ofContext(context).isPhone;
    return Center(
      child: SingleChildScrollView(
        padding: phone
            ? const EdgeInsets.fromLTRB(16, 12, 16, 16)
            : const EdgeInsets.all(20),
        child: Rise(
          duration: const Duration(milliseconds: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Headline(
                  'Ask about ',
                  name: workspace,
                  after: '.',
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: phone ? 14 : 22),
              ListenableBuilder(
                listenable: sources,
                builder: (context, _) {
                  final suggestions = [
                    // Only the first two switched-on files are named.
                    for (final s in suggestionsFor([
                      ...sources.files
                          .where((f) => f.on)
                          .map((f) => f.title)
                          .take(2),
                    ]))
                      _Suggestion(s.label, onTap: () => onSuggest(s.prompt)),
                  ];
                  return phone
                      ? Column(spacing: 14, children: suggestions)
                      : Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: suggestions,
                        );
                },
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
    final phone = ScreenClass.ofContext(context).isPhone;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Tappable(
        label: widget.text,
        onTap: widget.onTap,
        // A pill on one line; a label that wraps keeps its corners rather than bulging.
        radius: BorderRadius.circular(phone ? 24 : 19),
        color: t.panel,
        side: BorderSide(color: lit ?? (phone ? t.line2 : t.line)),
        hoverColor: Colors.transparent,
        child: Container(
          constraints: BoxConstraints(
            minHeight: phone ? 44 : 0,
            // A phone's column of suggestions keeps to the screen's width.
            maxWidth: phone ? MediaQuery.sizeOf(context).width - 32 : 520,
          ),
          padding: phone
              ? const EdgeInsets.symmetric(horizontal: 18, vertical: 10)
              : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            widget.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Type.sans(phone ? 15 : 14, color: lit ?? t.ink),
          ),
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

  /// Edit sits beside the bubble, at its foot, so nothing stands between it and the answer. On
  /// a phone the bubble stands alone, at most 300 wide, as the design canvas draws it, and a
  /// long press on it is Edit.
  @override
  Widget build(BuildContext context) {
    if (!ScreenClass.ofContext(context).isPhone) return _beside(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Semantics(
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Edit'): onEdit,
        },
        child: GestureDetector(
          onLongPress: onEdit,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: _bubble(context),
          ),
        ),
      ),
    );
  }

  Widget _beside(BuildContext context) => LayoutBuilder(
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
    final phone = ScreenClass.ofContext(context).isPhone;
    return Container(
      padding: phone
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: t.bubble,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(phone ? 24 : 20),
          topRight: Radius.circular(phone ? 24 : 20),
          bottomLeft: Radius.circular(phone ? 24 : 20),
          bottomRight: Radius.circular(phone ? 8 : 6),
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

/// Check now and Stop, for the last answer when the app lost touch with it on the relay.
class _LostActions extends StatelessWidget {
  const _LostActions();

  @override
  Widget build(BuildContext context) {
    final chat = AppScope.of(context).chat;
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) => ActionRow(alignment: WrapAlignment.start, [
        AppButton(
          chat.checking ? 'Checking…' : 'Check now',
          onPressed: chat.checking ? null : () => unawaited(chat.checkAnswer()),
        ),
        AppButton('Stop', onPressed: () => unawaited(chat.stopLost())),
      ]),
    );
  }
}

class _Answer extends StatefulWidget {
  const _Answer(this.turn, {this.last = false, this.retry});

  final Turn turn;

  /// Whether [turn] is the chat's last answer.
  final bool last;

  /// Retry, on the chat's last answer only.
  final _Retry? retry;

  @override
  State<_Answer> createState() => _AnswerState();
}

class _AnswerState extends State<_Answer> {
  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: widget.turn, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final (turn, retry) = (widget.turn, widget.retry);
    final split = splitReasoning(turn.text, streaming: turn.streaming);
    final failure = turn.streaming ? null : modelFailure(split.answer);
    final answered = split.answer.isNotEmpty && failure == null;
    // The caret ends the text being written where it can, and stands alone where it cannot.
    final inline = turn.streaming && answered && takesCaret(split.answer);
    final rate = answered ? _feedbackOf(context, turn) : null;
    // An answer cut short shows what came in the second ink, under why it stopped.
    final cut = !turn.streaming && (turn.stopped || turn.error != null);
    final phone = ScreenClass.ofContext(context).isPhone;
    final action = answerAction(context);
    // The red box asks again itself, so Retry does not show twice.
    final askAgain =
        turn.error != null && !turn.stillRunning && retry?.onPressed != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (turn.rejoined && turn.streaming) ...[
          Row(
            children: [
              const ReadyDot(gap: false),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Kept answering while the app was closed.',
                  style: Type.sans(12.5, color: Tokens.of(context).muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        if (failure != null)
          AlertBox(AlertKind.bad, 'The model did not answer', text: failure)
        else if (split.answer.isNotEmpty)
          AnswerBody(
            split.answer,
            label: AppScope.of(context).labelAnswers && !turn.streaming,
            muted: cut,
            caret: inline,
          ),
        if (turn.browsing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: BrowserChip(turn),
          )
        else if (turn.streaming && turn.status != null)
          _Status(turn.status!),
        if (turn.streaming)
          for (final request in turn.approvals)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: ApprovalCard(turn, request),
            ),
        if (turn.streaming && !inline)
          // The caret alone, as the design canvas draws it, from the send on, while a
          // model's reasoning is hidden too.
          const Padding(padding: EdgeInsets.only(top: 6), child: Caret()),
        if (turn.error case final error?) ...[
          const SizedBox(height: 10),
          if (turn.stillRunning)
            AlertBox(
              AlertKind.info,
              'Still being written',
              text:
                  'The connection dropped, but the answer keeps going on the server. It will '
                  'appear here when it’s done.',
              action: widget.last ? const _LostActions() : null,
            )
          else
            AlertBox(
              AlertKind.bad,
              'The answer stopped',
              text: error,
              action: askAgain
                  ? AppButton('Ask again', onPressed: retry!.onPressed)
                  : null,
            ),
        ],
        if (!turn.streaming &&
            turn.browserSteps.isNotEmpty &&
            AppScope.of(context).chat.cardsOf(turn).isEmpty) ...[
          const SizedBox(height: 10),
          BrowserChip(turn),
        ],
        if (!turn.streaming && turn.citations.isNotEmpty) ...[
          SizedBox(height: phone ? 10 : 12),
          _Citations(turn.citations),
        ],
        if (!turn.streaming && turn.files.isNotEmpty) ...[
          const SizedBox(height: 12),
          GeneratedFiles(turn.files),
        ],
        if (!turn.streaming && (answered || (retry != null && !askAgain))) ...[
          SizedBox(height: phone ? 10 : 6),
          // On a phone the buttons are 44 wide, side by side, and the row starts 12 to the
          // left, so the first icon lines up with the text.
          Transform.translate(
            offset: Offset(phone ? -12 : 0, 0),
            child: Wrap(
              spacing: phone ? 0 : 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (answered)
                  CopyButton(
                    split.answer,
                    tooltip: 'Copy answer',
                    box: action,
                    size: IconSize.xs,
                  ),
                if (AppScope.of(context).readAloud case final aloud?
                    when answered)
                  _ReadAloudButton(aloud, turn),
                if (retry case final retry? when !askAgain)
                  IconBtn(
                    'refresh',
                    tooltip: retry.tooltip,
                    onPressed: retry.onPressed,
                    box: action,
                    size: IconSize.xs,
                  ),
                if (turn.metrics != null || rate != null)
                  AnswerMore(turn, turn.metrics, rate: rate),
                // In Agent mode the server may go on to finish the answer and save it, which
                // shows when the chat is read again.
                if (turn.stopped)
                  Text(
                    'Stopped · the server may still save it',
                    style: Type.sans(12, color: Tokens.of(context).muted),
                  ),
              ],
            ),
          ),
        ],
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
      final action = answerAction(context);
      return IconBtn(
        reading ? 'stop' : 'speaker',
        tooltip: reading ? 'Stop reading' : 'Read aloud',
        onPressed: () => aloud.toggle(turn),
        box: action,
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

/// The sources an answer drew on, in one line that never wraps, so the answer keeps its height:
/// the first three by name, then the rest folded into one "+N" chip that lists them all in the
/// panel to the right, or on a phone in a sheet. A web page is named by its site.
class _Citations extends StatelessWidget {
  const _Citations(this.citations);

  final List<Citation> citations;

  /// How many are named before the rest fold.
  static const shown = 3;

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    final folded = citations.length > shown + 1;
    final named = folded ? citations.take(shown) : citations;
    return ListenableBuilder(
      listenable: shell,
      builder: (context, _) {
        final open = shell.citedOpen && identical(shell.cited, citations);
        return ClipRect(
          child: Row(
            spacing: 6,
            children: [
              for (final (i, citation) in named.indexed)
                Flexible(
                  child: _Citation(number: i + 1, citation: citation),
                ),
              if (folded)
                _MoreSources(
                  citations.length - shown,
                  open: open,
                  onTap: () => shell.toggleCited(citations),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// How many more sources an answer has, which lists them all; lit while they show.
class _MoreSources extends StatelessWidget {
  const _MoreSources(this.count, {required this.open, required this.onTap});

  final int count;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = ScreenClass.ofContext(context).isPhone;
    return Tappable(
      touchTarget: true,
      label: '$count more sources',
      toggled: open,
      onTap: onTap,
      radius: BorderRadius.circular(99),
      color: open ? t.sel : (phone ? t.panel : t.hover),
      side: phone ? BorderSide(color: t.line) : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: phone ? 36 : 0),
        child: Padding(
          padding: phone
              ? const EdgeInsets.symmetric(horizontal: 12)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              '+$count',
              style: Type.sans(
                phone ? 13.5 : 12.5,
                color: open ? t.accent : (phone ? t.ink2 : t.muted),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One source. A file in Sources lights up there when tapped, or on a phone, where Documents
/// is a sheet, opens the passages the answer read from it, when the server sent them; a web
/// page an agent read opens in the browser; anything else, such as a file since removed, only
/// shows its title.
class _Citation extends StatefulWidget {
  const _Citation({required this.number, required this.citation});

  final int number;
  final Citation citation;

  @override
  State<_Citation> createState() => _CitationState();
}

class _CitationState extends State<_Citation> {
  late final ShellController _shell;

  @override
  void initState() {
    super.initState();
    _shell = AppScope.of(context).shell;
  }

  @override
  void dispose() {
    // A citation that leaves the screen takes its sheet with it, after the frame.
    final (shell, citation) = (_shell, widget.citation);
    if (identical(shell.popup.value, citation)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => shell.closePopup(citation),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppScope.of(context).sources,
    builder: _build,
  );

  Widget _build(BuildContext context, Widget? _) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    final citation = widget.citation;
    final number = widget.number;
    final title = citation.title;
    final url = citation.url;
    final present = scope.sources.byTitle(title) != null;
    final live = present || url != null;
    final passages = present && citation.passages.isNotEmpty;
    final phone = ScreenClass.ofContext(context).isPhone;
    void close() => scope.shell.closePopup(citation);
    final chip = Tappable(
      label: present || url == null
          ? 'Source $number: $title'
          : 'Source $number: $title, opens in the browser',
      tooltip: passages
          ? 'Passages read'
          : present
          ? 'Show in Documents'
          : url?.toString(),
      // A phone shows the passages in a sheet over the chat, a desktop beside it.
      onTap: passages
          ? () => ScreenClass.ofContext(context).isPhone
                ? scope.shell.togglePopup(citation)
                : scope.shell.togglePassages(number, citation)
          : present
          ? () {
              scope.shell.openSources();
              scope.sources.flash(title);
            }
          : url == null
          ? null
          : () => openLink(context, url.toString()),
      radius: BorderRadius.circular(99),
      // On a phone a chip is the panel's colour, outlined, 32 tall, as the design canvas
      // draws it.
      color: phone ? t.panel : (live ? t.accentbg : t.hover),
      side: phone ? BorderSide(color: t.line) : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: phone ? 36 : 0),
        child: Padding(
          padding: phone
              ? const EdgeInsets.fromLTRB(8, 0, 12, 0)
              : const EdgeInsets.fromLTRB(6, 4, 10, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CitationNumber(number, live: live),
              const SizedBox(width: 6),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Text(
                    // A web page goes by its site, as a row of them reads best.
                    url?.host ?? title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: phone
                        ? Type.sans(13.5, color: t.ink2)
                        : Type.sans(12.5, color: live ? t.accent : t.ink2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!passages) return chip;
    // Only a citation that opens a sheet follows the popup.
    return ValueListenableBuilder(
      valueListenable: scope.shell.popup,
      child: chip,
      builder: (context, popup, chip) => PopupSheet(
        open: identical(popup, citation),
        onClose: close,
        title: 'Passages read',
        sheet: (context) =>
            PassagesView(number: number, citation: citation, onClose: close),
        child: chip!,
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
