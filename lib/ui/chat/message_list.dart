import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/chat.dart';
import '../../core/copy.dart';
import '../../core/prefs.dart';
import '../../core/shortcuts.dart';
import '../../core/server_models.dart';
import '../app_scope.dart';
import '../links.dart';
import '../shell_popup.dart';
import '../icons.dart';
import '../layout.dart';
import '../state/chat_controller.dart';
import '../state/turn.dart';
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
import '../widgets/tappable.dart';
import 'answer_body.dart';
import 'markdown_lists.dart';
import 'on_deck_view.dart';
import 'answer_menu.dart';
import 'citation_fit.dart';
import 'generated_files.dart';
import 'passages_sheet.dart';
import 'question_body.dart';
import 'sources_aside.dart';
import 'wait_line.dart';
import '../widgets/scroll_fades.dart';

/// The chat on screen, newest at the bottom. Empty, it invites a first question.
///
/// The list is reversed so it starts at the newest turn and stays pinned there as an answer
/// grows, and builds only the turns in view. Scrolled up from the newest text, what is in view
/// stays put while the answer grows below it. Its parent rebuilds it when the chat changes; a
/// streaming answer rebuilds only itself. Another chat opens at its newest turn, and a message
/// sent scrolls there. Scrolled up past [_MessageListState._jumpFrom], a round button over the
/// composer scrolls back to it.
///
/// A question sits 8 above its answer and each exchange is 28 below the one before. The latest
/// answer sits on a tile; older answers are flat. Once a question has scrolled up out of view
/// while its answer still runs under the top of the list, the question stays pinned there on one
/// line, and tapping it scrolls back to it.
class MessageList extends StatefulWidget {
  const MessageList({super.key, required this.onEdit, required this.onPutBack});

  /// Puts a sent message's text back in the composer, to send as a new message.
  final ValueChanged<String> onEdit;

  /// Puts a waiting message back in the composer, ahead of what is typed there.
  final ValueChanged<OnDeck> onPutBack;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final _scroll = ScrollController();

  /// [ChatController.sends] when the list was last built.
  int? _sends;

  /// How far from the newest text the list may sit and still count as at the bottom.
  static const _atBottom = 8.0;

  /// How far from the newest text the list must sit for the jump button to show.
  static const _jumpFrom = 48.0;

  /// Whether the list sits more than [_jumpFrom] from the newest text, as its last scroll or
  /// change of size left it.
  final _away = ValueNotifier(false);

  /// The newest turn's height as last laid out.
  final _newest = _Extent();

  /// The waiting messages' height as last laid out.
  final _waiting = _Extent();

  /// The waiting messages, which go with the newest turn as turns are added, keeping their
  /// state.
  final _waitingKey = GlobalKey();

  /// The question pinned over the top of the list, or null.
  final _pinned = ValueNotifier<Turn?>(null);

  /// The older answer whose Copy and More show, once tapped.
  final _revealed = ValueNotifier<Turn?>(null);

  /// The list's area, which the turns' places are measured from.
  final _area = GlobalKey();

  /// Whether [_pinned] is to be worked out again after this frame.
  bool _pinQueued = false;

  /// How tall the pinned question's bar is, its rule included.
  static const _pinBar = _PinnedQuestion.height + 1;

  /// How far a question sits above its answer, and an exchange below the one before.
  static const _toAnswer = 8.0;
  static const _toExchange = 28.0;

  @override
  void dispose() {
    _scroll.dispose();
    _away.dispose();
    _pinned.dispose();
    _revealed.dispose();
    super.dispose();
  }

  /// Works out [_pinned] again once this frame is laid out, so the turns' places are current.
  void _queuePin() {
    if (_pinQueued) return;
    _pinQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinQueued = false;
      if (mounted) _pinned.value = _pinnedQuestion();
    });
  }

  /// [turn]'s box and where its top sits under the top of the list, or null while it is not
  /// laid out.
  (RenderBox, double)? _placeOf(Turn turn) {
    final area = _area.currentContext?.findRenderObject();
    final box = _keyOf(turn).currentContext?.findRenderObject();
    if (area is! RenderBox || box is! RenderBox || !box.attached) return null;
    if (!area.hasSize || !box.hasSize) return null;
    return (box, box.localToGlobal(Offset.zero, ancestor: area).dy);
  }

  /// The question whose answer runs under the pinned bar's place while the question itself sits
  /// above it, out of view; null when the turn there is a question, or none is.
  Turn? _pinnedQuestion() {
    final turns = AppScope.of(context).chat.turns;
    for (var at = turns.length - 1; at > 0; at--) {
      final answer = turns[at];
      final question = turns[at - 1];
      if (answer.role == Role.user || question.role != Role.user) continue;
      // Turns far below the view are not laid out; the first one up there that is, is.
      if (_placeOf(answer) case (final box, final top)) {
        if (top >= _pinBar) continue;
        return top + box.size.height > _pinBar ? question : null;
      }
    }
    return null;
  }

  /// Scrolls back to [question], whose bubble comes to rest where the list's padding starts.
  /// A question far up a long answer is not laid out yet, so the list first brings its answer's
  /// top into view, and finds the question from there.
  void _toQuestion(Turn question) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final turns = AppScope.of(context).chat.turns;
    final at = turns.indexOf(question);
    if (at < 0) return;
    // The list is reversed, so its offset counts up as older turns come down into view.
    double to(double top) => (position.pixels - top).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (_placeOf(question) case (_, final top)) {
      final above = at == 0 ? 0.0 : _toExchange;
      _scroll.glideTo(
        context,
        to(top + above - 12),
        const Duration(milliseconds: 250),
      );
      return;
    }
    if (at + 1 >= turns.length) return;
    if (_placeOf(turns[at + 1]) case (_, final top)) {
      _scroll.jumpTo(to(top - position.viewportDimension / 2));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _placeOf(question) != null) _toQuestion(question);
      });
    }
  }

  /// Follows the list's offset, which a scroll changes and so does the newest turn growing
  /// while [_HoldPlace] keeps what is in view put. A code block's own sideways scroll is
  /// deeper and is left out.
  bool _onScroll(Notification n) {
    final metrics = switch (n) {
      ScrollNotification(depth: 0, :final metrics) => metrics,
      ScrollMetricsNotification(depth: 0, :final metrics) => metrics,
      _ => null,
    };
    if (metrics != null && metrics.axis == Axis.vertical) {
      _away.value = metrics.pixels > _jumpFrom;
      _queuePin();
    }
    return false;
  }

  /// Scrolls to the newest text, at once when the device asks for less motion.
  void _toNewest() {
    if (!_scroll.hasClients) return;
    _scroll.glideTo(context, 0, const Duration(milliseconds: 250));
  }

  /// Whether the newest turn's growth should leave what is in view put rather than push it up:
  /// always while the list is scrolled up from the newest text, and while an answer streams
  /// with [ChatSwitch.followAnswer] off. The list is reversed, so its offset counts up from the
  /// newest text.
  bool _holds(Turn? newest, PrefsController prefs) {
    if (_scrolledUp()) return true;
    return newest != null &&
        newest.streaming &&
        !prefs.prefs.isOn(ChatSwitch.followAnswer);
  }

  /// Whether the list is scrolled up from the newest text, where a change to the waiting
  /// messages under it leaves what is in view put.
  bool _scrolledUp() =>
      _scroll.hasClients && _scroll.position.pixels > _atBottom;

  /// Scrolls to the newest turn after this frame when a message was sent since the last build.
  void _follow(ChatController chat) {
    final sent = _sends != null && chat.sends != _sends;
    _sends = chat.sends;
    if (!sent) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && _scroll.offset != 0) _toNewest();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final chat = scope.chat;
    final workspace = chat.active;
    final turns = chat.turns;
    if (workspace == null) return const SizedBox.shrink();
    // The turns are built once below and held, so the list is built again, and they with it,
    // when the system's text size changes while the chat shows.
    MediaQuery.textScalerOf(context);
    _follow(chat);
    _queuePin();
    if (turns.isEmpty) {
      return _Empty(workspace: workspace.name);
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
    final latest = turns.lastIndexWhere((t) => t.role != Role.user);
    // A pull down past the oldest turn reads the chat again.
    // The list is reversed, so a long chat opens at its newest turn; it is as tall as its turns
    // and sits at the top, so a short chat starts under the header, as the Lite prototype
    // draws it.
    final list = CustomScrollView(
      // Another chat gets a list of its own, which starts at its newest turn.
      key: ValueKey((chat.activeSlug, chat.activeThread)),
      controller: _scroll,
      reverse: true,
      shrinkWrap: true,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          sliver: _HoldPlace(
            newest: _newest,
            waiting: _waiting,
            holds: () => _holds(turns.lastOrNull, scope.prefs),
            scrolledUp: _scrolledUp,
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _turn(chat, turns, i, latest: latest),
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
    final top = Align(
      key: _area,
      alignment: Alignment.topCenter,
      child: NotificationListener<Notification>(
        onNotification: _onScroll,
        child: ScrollFades(child: list),
      ),
    );
    // MessageList is built afresh as the chat changes, so this follows refreshing.
    return Stack(
      children: [
        Positioned.fill(
          child: PullRefresh(
            refreshing: chat.refreshing,
            onRefresh: chat.refresh,
            child: top,
          ),
        ),
        // Centred 8 above the composer, whose own padding puts it 16 above its card.
        Positioned(
          left: 0,
          right: 0,
          bottom: 8,
          child: ValueListenableBuilder(
            valueListenable: _away,
            builder: (context, away, _) => away
                ? Center(child: _JumpButton(onTap: _toNewest))
                : const SizedBox.shrink(),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder(
            valueListenable: _pinned,
            builder: (context, question, _) => question == null
                ? const SizedBox.shrink()
                : _PinnedQuestion(
                    question.text,
                    onTap: () => _toQuestion(question),
                  ),
          ),
        ),
      ],
    );
  }

  /// The messages waiting to be sent, under the newest turn.
  Widget _onDeck() => _Measured(
    key: _waitingKey,
    into: _waiting,
    child: OnDeckView(onPutBack: widget.onPutBack),
  );

  /// The [i]th turn from the newest; [latest] is the place in [turns] of the latest answer.
  Widget _turn(
    ChatController chat,
    List<Turn> turns,
    int i, {
    required int latest,
  }) {
    final scope = AppScope.of(context);
    final at = turns.length - 1 - i;
    final turn = turns[at];
    final first = at == 0;
    final answers =
        turn.role != Role.user && !first && turns[at - 1].role == Role.user;
    final above = first ? 0.0 : (answers ? _toAnswer : _toExchange);
    return _Measured(
      key: _keyOf(turn),
      into: i == 0 ? _newest : null,
      turn: turn,
      child: Center(
        // The column's full width, or the chat's where that is narrower, so a short answer
        // starts at its left edge rather than shrinking to its text and sitting in the middle.
        child: SizedBox(
          width: Sizes.column,
          // The newest turn holds the messages waiting under it, so its place in the list
          // keeps what is in view put as either changes.
          child: _withWaiting(
            newest: i == 0,
            Padding(
              padding: EdgeInsets.only(top: above),
              child: Rise(
                child: turn.role == Role.user
                    ? ListenableBuilder(
                        // Only a shortcut's bubble depends on the preference.
                        listenable: turn.shortcutUse == null
                            ? turn
                            : Listenable.merge([turn, scope.prefs]),
                        builder: (context, _) => _UserBubble(
                          turn.text,
                          attachments: turn.attachments,
                          shortcutUse: turn.shortcutUse,
                          hideShortcutPrompt:
                              turn.shortcutUse != null &&
                              scope.prefs.prefs.isOn(
                                ChatSwitch.hideShortcutPrompts,
                              ),
                          notSent: turn.notSent,
                          onTryAgain: chat.canSendAgain(turn)
                              ? () => unawaited(chat.sendAgain(turn))
                              : null,
                          onEdit: () {
                            chat.discard(turn);
                            widget.onEdit(turn.text);
                          },
                        ),
                      )
                    : _Answer(
                        turn,
                        revealed: _revealed,
                        retry: i == 0 ? _retryOf(chat) : null,
                        latest: at == latest,
                        onWithoutPicture: answers
                            ? () => widget.onEdit(turns[at - 1].text)
                            : null,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [turn], over the waiting messages when it is the [newest]. Every turn has the same shape,
  /// so the one that was newest keeps its state when another is added.
  Widget _withWaiting(Widget turn, {required bool newest}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [turn, if (newest) _onDeck()],
  );
}

/// The latest answer's tile: [Tokens.tile] inside its [Tokens.tileEdge], on the tile's shadow,
/// reaching [out] past the column on each side, its text inside the edge and [pad].
class _OnTile extends StatelessWidget {
  const _OnTile({required this.child});

  final Widget child;

  static const out = 8.0;
  static const pad = 16.0;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return LayoutBuilder(
      builder: (context, box) => OverflowBox(
        fit: OverflowBoxFit.deferToChild,
        minWidth: box.maxWidth + 2 * out,
        maxWidth: box.maxWidth + 2 * out,
        child: Container(
          padding: const EdgeInsets.all(pad),
          decoration: BoxDecoration(
            color: t.tile,
            border: Border.all(color: t.tileEdge),
            borderRadius: BorderRadius.circular(24),
            boxShadow: t.tileShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The question of the answer being read, pinned over the top of the list once it has scrolled
/// out of view: one line, cut short with an ellipsis, on the ground over a rule. Tapping it
/// scrolls back to the question.
class _PinnedQuestion extends StatelessWidget {
  const _PinnedQuestion(this.text, {required this.onTap});

  final String text;
  final VoidCallback onTap;

  /// Its height, without the rule under it.
  static const height = 44.0;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.ground,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Tappable(
        label: 'Back to the question: $line',
        excludeSemantics: true,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: height),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                AppIcon('arrowUp', size: IconSize.small, color: t.ink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    line,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(Type.chat, color: t.ink, height: 1.5),
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

/// The round button over the composer that scrolls the chat back to its newest text: 48 across
/// on [Tokens.tile], inside its [Tokens.tileEdge], floating on the tile's shadow.
class _JumpButton extends StatelessWidget {
  const _JumpButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: t.tileShadow,
      ),
      child: Tappable(
        label: 'Jump to the newest message',
        tooltip: 'Jump to the newest message',
        onTap: onTap,
        shape: CircleBorder(side: BorderSide(color: t.tileEdge)),
        color: t.tile,
        child: SizedBox.square(
          dimension: 48,
          child: Center(
            child: AppIcon('arrowDown', size: IconSize.normal, color: t.ink),
          ),
        ),
      ),
    );
  }
}

/// A height as it was last laid out, a turn's or the waiting messages', written by [_Measured]
/// during its own layout, where reading it is allowed.
class _Extent {
  /// The turn laid out, or null for the waiting messages.
  Turn? turn;
  double height = 0;

  /// Whether it was laid out since [_RenderHoldPlace] last looked.
  bool fresh = false;
}

/// [child], which writes its height into [into] each time it is laid out.
class _Measured extends SingleChildRenderObjectWidget {
  const _Measured({
    super.key,
    required this.into,
    this.turn,
    required Widget super.child,
  });

  final _Extent? into;
  final Turn? turn;

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
  Turn? turn;

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

/// The turns' list, which keeps what is in view put when the newest turn grows while [holds],
/// and when the waiting messages under it change while [scrolledUp]: in the same layout, it moves
/// the scroll offset by as much as they grew or shrank, so nothing that was drawn moves.
class _HoldPlace extends SingleChildRenderObjectWidget {
  const _HoldPlace({
    required this.newest,
    required this.waiting,
    required this.holds,
    required this.scrolledUp,
    required Widget sliver,
  }) : super(child: sliver);

  final _Extent newest;
  final _Extent waiting;
  final bool Function() holds;
  final bool Function() scrolledUp;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHoldPlace(newest, waiting, holds, scrolledUp);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHoldPlace renderObject,
  ) => renderObject
    ..newest = newest
    ..waiting = waiting
    ..holds = holds
    ..scrolledUp = scrolledUp;
}

class _RenderHoldPlace extends RenderProxySliver {
  _RenderHoldPlace(this.newest, this.waiting, this.holds, this.scrolledUp);

  _Extent newest;
  _Extent waiting;
  bool Function() holds;
  bool Function() scrolledUp;

  /// The newest turn and its height at the last layout that laid it out.
  Turn? _turn;
  double _height = 0;

  /// The waiting messages' height at the last layout that laid them out.
  double _waitingHeight = 0;

  @override
  void performLayout() {
    newest.fresh = false;
    waiting.fresh = false;
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
    final same = identical(newest.turn, _turn);
    final grown = same ? newest.height - _height : 0.0;
    // The newest turn holds the waiting messages, whose own change counts apart.
    final was = _waitingHeight;
    final waited = waiting.fresh && same ? waiting.height - was : 0.0;
    _turn = newest.turn;
    _height = newest.height;
    if (waiting.fresh) _waitingHeight = waiting.height;
    var moved = 0.0;
    if (grown - waited > 0.5 && holds()) moved += grown - waited;
    if (waited.abs() > 0.5 && scrolledUp()) moved += waited;
    // Never below the newest text.
    moved = moved.clamp(-constraints.scrollOffset, double.infinity);
    if (moved.abs() > 0.5) {
      geometry = SliverGeometry(scrollOffsetCorrection: moved);
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.workspace});

  final String workspace;

  @override
  Widget build(BuildContext context) {
    // Built once, so the keyboard sliding in lays the hero out again without rebuilding it.
    final hero = Center(child: _Hero(workspace));
    // Centred in the room the keyboard leaves, a little above the middle: the header sits over
    // it and the composer under it, so the true middle reads low. It moves up with the keyboard
    // because the list is laid out in the space above it.
    return LayoutBuilder(
      builder: (context, box) {
        final below = (box.maxHeight * 0.085).clamp(0.0, 72.0);
        final pad = EdgeInsets.fromLTRB(16, 16, 16, 16 + below);
        return SingleChildScrollView(
          padding: pad,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (box.maxHeight - pad.vertical).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: hero,
          ),
        );
      },
    );
  }
}

/// Ask about the workspace, which switches it, over its documents in use, which open Documents.
class _Hero extends StatelessWidget {
  const _Hero(this.workspace);

  final String workspace;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final sources = scope.sources;
    final titleStyle = Headline.styleOf(context).copyWith(
      fontWeight: FontWeight.w700,
      fontVariations: const [FontVariation('wght', 700)],
      color: Tokens.of(context).accent,
    );
    return Rise(
      duration: const Duration(milliseconds: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: double.infinity,
            child: Headline('Ask about', textAlign: TextAlign.center),
          ),
          const SizedBox(height: 6),
          ListenableBuilder(
            listenable: scope.shell.popup,
            builder: (context, _) => SizedBox(
              width: MediaQuery.sizeOf(context).width - 32,
              child: Tappable(
                label: 'Workspace: $workspace. Switch workspace',
                expanded: scope.shell.menuOpen,
                radius: BorderRadius.circular(Sizes.small),
                onTap: () => scope.shell.togglePopup(Popup.workspaces),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: Tappable.touchSide,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    // The chevron sits against the name, so it reads as part of what opens.
                    children: [
                      Flexible(
                        child: Text(
                          workspace,
                          textAlign: TextAlign.center,
                          style: titleStyle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      AppIcon(
                        'down',
                        size: IconSize.row,
                        color: Tokens.of(context).muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          ListenableBuilder(
            listenable: sources,
            builder: (context, _) {
              if (sources.loading || sources.read == null) {
                return const SizedBox.shrink();
              }
              final label = sources.onCount > 0
                  ? '${plural(sources.onCount, 'document', 'documents')} in use'
                  : sources.files.isNotEmpty
                  ? 'No documents in use'
                  : 'No documents yet';
              return Tappable(
                label: '$label. Open Documents',
                radius: BorderRadius.circular(Sizes.small),
                onTap: () =>
                    scope.shell.openSources(asPane: Wide.split(context)),
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width - 32,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: Tappable.touchSide,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(
                          'doc',
                          size: IconSize.xs,
                          color: Tokens.of(context).ink,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Type.note(Tokens.of(context).ink),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AppIcon(
                          'chevron',
                          size: IconSize.tiny,
                          color: Tokens.of(context).ink,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

AskAgain _retryOf(ChatController chat) {
  final turns = chat.turns;
  final files =
      turns.length >= 2 && turns[turns.length - 2].attachments.isNotEmpty;
  return (
    onPressed: chat.canRetry ? chat.retry : null,
    heard: files
        ? 'Ask again is off: the files sent with the question are not kept'
        : 'Ask again',
  );
}

class _UserBubble extends StatelessWidget {
  const _UserBubble(
    this.text, {
    this.attachments = const [],
    this.shortcutUse,
    this.hideShortcutPrompt = false,
    this.notSent = false,
    this.onTryAgain,
    required this.onEdit,
  });

  final String text;

  /// The files sent with the question: a picture drawn small, any other by its name.
  final List<SentFile> attachments;
  final ShortcutUse? shortcutUse;
  final bool hideShortcutPrompt;

  /// Whether the message never reached the server: its edge is red, with Not sent under it.
  final bool notSent;

  /// Sends it again, or null when that cannot be done now or the files it carried are gone.
  final VoidCallback? onTryAgain;

  /// Puts [text] back in the composer, to ask again as a new message.
  final VoidCallback onEdit;

  /// The bubble stands alone, at most 300 wide, as the Lite prototype draws it, and a long press
  /// on it is Edit. A message that was not sent has Not sent, Try again and Edit under it.
  @override
  Widget build(BuildContext context) {
    final bubble = Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Edit'): onEdit,
      },
      child: GestureDetector(
        onLongPress: onEdit,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: questionWidth),
          child: _bubble(context),
        ),
      ),
    );
    if (!notSent) return Align(alignment: Alignment.centerRight, child: bubble);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        bubble,
        // The buttons are 44 tall, so the row tucks up under the bubble and out to the right.
        Transform.translate(
          offset: const Offset(12, -6),
          child: _NotSent(onTryAgain: onTryAgain, onEdit: onEdit),
        ),
      ],
    );
  }

  Widget _bubble(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: questionPadding,
      decoration: BoxDecoration(
        color: t.accentSoft,
        border: notSent ? Border.all(color: t.danger) : null,
        borderRadius: questionRadius,
      ),
      child: QuestionBody(
        text,
        attachments: attachments,
        shortcutUse: hideShortcutPrompt ? shortcutUse : null,
      ),
    );
  }
}

/// What stands under a message that did not reach the server: Not sent beside the danger mark,
/// then Try again, which sends it as it was, and Edit, which puts its words back in the message
/// box.
class _NotSent extends StatelessWidget {
  const _NotSent({required this.onTryAgain, required this.onEdit});

  final VoidCallback? onTryAgain;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            Status.danger.icon,
            size: IconSize.small,
            color: Status.danger.color(t),
          ),
          const SizedBox(width: 6),
          Text('Not sent', style: Type.caption(t.ink, weight: FontWeight.w600)),
          const SizedBox(width: 6),
          if (onTryAgain case final again?)
            TextAction.plain('Try again', again),
          TextAction.plain('Edit', onEdit),
        ],
      ),
    );
  }
}

/// In place of a failure that says the workspace's chat model takes text only: Picture
/// refused., with Remove the picture, which puts the question's words back in the message box,
/// without the picture, to send again.
class _NoPictures extends StatelessWidget {
  const _NoPictures({required this.onWithoutPicture});

  final VoidCallback? onWithoutPicture;

  @override
  Widget build(BuildContext context) => AlertBox(
    AlertKind.bad,
    'Picture refused.',
    text: 'This chat model can’t read pictures. Send your message without the picture.',
    inline: true,
    action: switch (onWithoutPicture) {
      final again? => AppButton('Remove the picture', onPressed: again),
      null => null,
    },
  );
}

/// An answer. The latest sits on a tile with Copy and More under it; an older one shows them
/// once tapped, and a tap again hides them. A long press on an answer, or a screen reader's
/// More, opens its Answer sheet ([AnswerSheets]). A failure says why in a red box in few words
/// ([failureText]), with Ask again in the box on the chat's last answer; a failed answer's
/// words keep Copy but not More.
class _Answer extends StatelessWidget {
  const _Answer(
    this.turn, {
    required this.revealed,
    this.retry,
    this.latest = false,
    this.onWithoutPicture,
  });

  final Turn turn;

  /// The older answer whose actions show, as the last tap left it.
  final ValueNotifier<Turn?> revealed;

  /// Ask again, on the chat's last answer only.
  final AskAgain? retry;

  /// Whether this is the chat's latest answer.
  final bool latest;

  /// Puts the question's words back in the message box, for a model that refused its picture.
  final VoidCallback? onWithoutPicture;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([turn, revealed]),
    builder: (context, _) => _Quiet(
      turn,
      builder: (context, quiet) {
        final answer = _build(context, quiet: quiet);
        // Gone quiet before any words, the card stands alone under the question.
        final alone = quiet && turn.text.trim().isEmpty;
        return latest && !alone ? _OnTile(child: answer) : answer;
      },
    ),
  );

  Widget _build(BuildContext context, {required bool quiet}) {
    final shell = AppScope.of(context).shell;
    final split = splitReasoning(turn.text, streaming: turn.streaming);
    final failure = turn.streaming ? null : modelFailure(split.answer);
    final answered = split.answer.isNotEmpty && failure == null;
    // The caret ends the text being written where it can, and stands alone where it cannot.
    final inline = turn.streaming && answered && takesCaret(split.answer);
    // An answer cut short shows what came in the second ink, under why it stopped.
    final cut = !turn.streaming && turn.unfinished;
    // The red box asks again itself, so Ask again does not show twice. The box for a model
    // that cannot see pictures asks for the question without its picture instead, and a
    // question with a picture cannot be asked again as it was.
    final error = turn.error;
    final noPictures =
        (error != null && refusesPictures(error)) ||
        (failure != null && refusesPictures(failure));
    final askAgain =
        (error != null || failure != null) &&
        !noPictures &&
        retry?.onPressed != null;
    AppButton? again({bool primary = false}) => askAgain
        ? AppButton(
            'Ask again',
            primary: primary,
            compact: true,
            onPressed: retry!.onPressed,
          )
        : null;
    final settled = !turn.streaming && answered;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (failure != null && noPictures)
          _NoPictures(onWithoutPicture: onWithoutPicture)
        else if (failure != null)
          AlertBox(
            AlertKind.bad,
            'The model',
            text: 'didn’t answer. Ask again in a minute.',
            inline: true,
            action: again(),
          )
        else if (split.answer.isNotEmpty)
          AnswerBody(
            split.answer,
            muted: cut,
            caret: inline,
            selectable: false,
          ),
        // Until the first words, while a model's reasoning is hidden too, what it waits on.
        if (turn.streaming && split.answer.isEmpty)
          quiet ? const _NoNews() : WaitLine(turn)
        else ...[
          if (turn.streaming && turn.status != null) _Status(turn.status!),
          if (turn.streaming && !inline)
            // The caret alone where the text cannot end with it, as in a code fence.
            const Padding(padding: EdgeInsets.only(top: 6), child: Caret()),
          if (quiet) ...[const SizedBox(height: 10), const _NoNews()],
        ],
        // Where the words stopped coming, once the connection dropped, unless the server is
        // known to be writing the rest.
        if (split.answer.isNotEmpty &&
            !turn.streaming &&
            switch (turn.dropped) {
              Dropped.lost => turn.waiting,
              Dropped.unsaved || Dropped.movedOn => true,
              Dropped.answering || null => false,
            }) ...[
          const SizedBox(height: 8),
          _StoppedHere(saved: turn.dropped != Dropped.unsaved),
        ],
        if (turn.mayBeCut) ...[
          const SizedBox(height: 4),
          _MayBeCut(onAskAgain: retry?.onPressed),
        ],
        if (turn.waiting) ...[
          const SizedBox(height: 10),
          _Dropped(turn.dropped),
        ],
        if (error != null && noPictures) ...[
          const SizedBox(height: 10),
          _NoPictures(onWithoutPicture: onWithoutPicture),
        ] else if (error != null && turn.dropped == Dropped.unsaved)
        // Nothing came of the question at all, so asking again is what is left.
        ...[
          const SizedBox(height: 10),
          AlertBox(
            AlertKind.bad,
            'Answer stopped',
            text: error,
            action: again(primary: true),
          ),
        ] else if (error != null) ...[
          const SizedBox(height: 10),
          AlertBox(
            AlertKind.bad,
            'Answer stopped.',
            text: failureText(error),
            inline: true,
            action: again(),
          ),
        ],
        if (!turn.streaming && turn.citations.isNotEmpty) ...[
          const SizedBox(height: 8),
          _Citations(turn),
        ],
        if (!turn.streaming && turn.files.isNotEmpty) ...[
          const SizedBox(height: 12),
          GeneratedFiles(turn.files),
        ],
        if (!turn.streaming &&
            (answered || (retry != null && !askAgain && !noPictures))) ...[
          const SizedBox(height: 8),
          AnswerActions(
            turn,
            answer: answered ? split.answer : '',
            shown: latest || identical(revealed.value, turn),
            askAgain: askAgain ? null : retry,
            // A failed answer's words can be copied; the box says the rest.
            more: error == null,
          ),
        ],
      ],
    );
    if (!settled) return column;
    void openSheet() => shell.togglePopup(answerSheetOf(turn));
    return AnswerSheets(
      turn,
      answer: split.answer,
      askAgain: askAgain ? null : retry,
      child: Semantics(
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'More'): openSheet,
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: latest
              ? null
              : () => revealed.value = identical(revealed.value, turn)
                    ? null
                    : turn,
          onLongPress: openSheet,
          child: column,
        ),
      ),
    );
  }
}

/// The card of an answer whose connection dropped while its chat is read for what the server
/// saved: Connection lost while no read has reached the server since, and Still answering on
/// the server once one has and the answer is not saved yet; each with Check now, which reads
/// the chat at once ([ChatController.checkWaiting]).
class _Dropped extends StatelessWidget {
  const _Dropped(this.how);

  final Dropped? how;

  @override
  Widget build(BuildContext context) {
    final chat = AppScope.of(context).chat;
    final check = AppButton(
      'Check now',
      onPressed: () => unawaited(chat.checkWaiting()),
    );
    if (how == Dropped.answering) {
      return AlertBox(
        AlertKind.info,
        'Still answering on the server',
        text:
            'The connection dropped. AnythingLLM keeps going, and the answer shows here once '
            'it is saved.',
        action: check,
      );
    }
    // A warning is not a live region of its own, and this one changes as the chat is read.
    return Semantics(
      liveRegion: true,
      container: true,
      child: AlertBox(
        AlertKind.warn,
        'Connection lost',
        text: 'Checking what the server saved.',
        action: check,
      ),
    );
  }
}

/// Under the words of an answer whose connection dropped: a stop mark and Stopped here, with
/// `not saved` once the server saved no answer.
class _StoppedHere extends StatelessWidget {
  const _StoppedHere({required this.saved});

  /// False once the server is known to have saved no answer.
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      spacing: 6,
      children: [
        // A filled square, as a stop mark is drawn on the boards.
        SizedBox.square(
          dimension: IconSize.small.px,
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: t.ink,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
        Flexible(
          child: Text(
            saved ? 'Stopped here' : 'Stopped here · not saved',
            style: Type.note(t.ink),
          ),
        ),
      ],
    );
  }
}

/// Under an answer read from the server after its connection dropped, in a mode in which the
/// server stops it once it notices ([Turn.mayBeCut]): This answer may be cut short., with Ask
/// again where it can run.
class _MayBeCut extends StatelessWidget {
  const _MayBeCut({required this.onAskAgain});

  final VoidCallback? onAskAgain;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Tappable.touchSide),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                AppIcon(
                  Status.warning.icon,
                  size: IconSize.small,
                  color: Status.warning.color(t),
                ),
                Flexible(
                  child: Text(
                    'This answer may be cut short.',
                    style: Type.body(t.ink),
                  ),
                ),
              ],
            ),
          ),
          if (onAskAgain case final ask?)
            Tappable(
              label: 'Ask again',
              onTap: ask,
              radius: BorderRadius.circular(Sizes.small),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: Tappable.touchSide,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Text(
                      'Ask again',
                      style: Type.body(t.accent, weight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Builds an answer with whether it is [Turn.quiet], again each time it falls quiet: while it
/// streams, a timer waits for the moment [Turn.quietAfter] has passed since the server last sent
/// something, and a piece arriving meanwhile, which rebuilds this, starts the wait again.
class _Quiet extends StatefulWidget {
  const _Quiet(this.turn, {required this.builder});

  final Turn turn;
  final Widget Function(BuildContext context, bool quiet) builder;

  @override
  State<_Quiet> createState() => _QuietState();
}

class _QuietState extends State<_Quiet> {
  Timer? _due;

  @override
  void dispose() {
    _due?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _due?.cancel();
    _due = null;
    final turn = widget.turn;
    final heard = turn.heard;
    if (turn.streaming && heard != null && !turn.quiet) {
      final left = Turn.quietAfter - clock.now().difference(heard);
      _due = Timer(left, () {
        if (mounted) setState(() {});
      });
    }
    return widget.builder(context, turn.quiet);
  }
}

/// The card of an answer that has gone [Turn.quiet]: No news from the server for 30 seconds,
/// with Check, which reads the chat to see whether the server is still there or already saved
/// the answer ([ChatController.checkQuiet]), and Stop.
class _NoNews extends StatelessWidget {
  const _NoNews();

  @override
  Widget build(BuildContext context) {
    final chat = AppScope.of(context).chat;
    return Semantics(
      liveRegion: true,
      container: true,
      child: AlertBox(
        AlertKind.warn,
        'No news',
        text: 'from the server for ${Turn.quietAfter.inSeconds} seconds.',
        inline: true,
        action: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            AppButton('Check', onPressed: () => unawaited(chat.checkQuiet())),
            AppButton('Stop', onPressed: chat.stop),
          ],
        ),
      ),
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
          style: Type.note(t.ink).copyWith(fontStyle: FontStyle.italic),
        ),
      ),
    );
  }
}

/// The sources an answer drew on, in one line that never wraps, so the answer keeps its height:
/// the first by name, as many as fit with at least [readable] characters of their names and at
/// most two, then the rest folded into one "+N more" chip that lists them all in a sheet
/// ([fitChips]), so the answer never drowns in its sources. A web page is named by its site. On a wide window a
/// chip picks its source, and +N the answer, in the Sources panel beside the chat instead.
class _Citations extends StatelessWidget {
  const _Citations(this.turn);

  final Turn turn;

  /// How many are named before the rest fold, at most.
  static const shown = 2;

  /// The fewest characters of a name a chip shows; one that can't fit them folds.
  static const readable = 8;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final citations = turn.citations;
      final scaler = MediaQuery.textScalerOf(context);
      // As a [Text] draws it: over the style around it, which may space its letters.
      final around = DefaultTextStyle.of(context).style;
      double widthOf(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: around.merge(style)),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final width = painter.width.ceilToDouble();
        painter.dispose();
        return width;
      }

      // Only the ones that may lead the line are measured; the rest can only fold.
      final most = math.min(citations.length, shown);
      final names = [for (final c in citations.take(most)) citedName(c)];
      final whole = [
        for (final name in names)
          _Citation.frame + widthOf(name, _Citation.nameStyle),
      ];
      final least = [
        for (final (i, name) in names.indexed)
          math.min(
            whole[i],
            _Citation.frame +
                widthOf(
                  '${name.characters.take(readable)}…',
                  _Citation.nameStyle,
                ),
          ),
      ];
      final widths = fitChips(
        // Its whole name where the line has room: the line stays one line, so a wide chip
        // costs the answer no height.
        natural: whole,
        readable: least,
        count: citations.length,
        // As wide as it can be: holding them all.
        more: math.max(
          Tappable.touchSide,
          _MoreSources.frame +
              widthOf('+${citations.length} more', _MoreSources.style),
        ),
        width: box.maxWidth,
        gap: _Citation.apart,
      );
      return _line(context, widths);
    },
  );

  Widget _line(BuildContext context, List<double> widths) {
    final shell = AppScope.of(context).shell;
    final citations = turn.citations;
    final folded = citations.length > widths.length;
    final named = citations.take(widths.length);
    final beside = Wide.split(context);
    final follow = FollowedScope.of(context);
    return ListenableBuilder(
      listenable: beside ? follow : shell,
      builder: (context, _) {
        final picked = beside ? follow.value : null;
        final mine = picked != null && identical(picked.turn, turn);
        final open = beside
            ? mine && picked.source == null
            : shell.citedOpen && identical(shell.cited, citations);
        // The line is as tall as its chips' hit areas, a finger's [Tappable.touchSide].
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Tappable.touchSide),
          child: Align(
            alignment: Alignment.centerLeft,
            heightFactor: 1,
            child: ClipRect(
              child: Row(
                spacing: _Citation.apart,
                children: [
                  for (final (i, citation) in named.indexed)
                    SizedBox(
                      width: widths[i],
                      child: _Citation(
                        number: i + 1,
                        citation: citation,
                        // Beside the panel, a chip picks its source there.
                        onPick: beside
                            ? () => shell.aside.value = AsideChoice(turn, i)
                            : null,
                        picked: mine && picked.source == i,
                      ),
                    ),
                  if (folded)
                    _MoreSources(
                      citations.length - widths.length,
                      of: citations.length,
                      open: open,
                      onTap: beside
                          ? () => shell.aside.value = AsideChoice(turn)
                          : () => shell.toggleCited(citations),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// How many more sources an answer has, which lists them all; lit while they show.
class _MoreSources extends StatelessWidget {
  const _MoreSources(
    this.count, {
    required this.of,
    required this.open,
    required this.onTap,
  });

  final int count;

  /// How many sources the answer has in all.
  final int of;
  final bool open;
  final VoidCallback onTap;

  /// Its count's style, but for the colour.
  static final style = Type.caption(
    const Color(0x00000000),
    weight: FontWeight.w600,
  );

  /// Its width around its count.
  static const frame = 2 * _pad;
  static const _pad = 12.0;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      touchTarget: true,
      label: '$count more sources. Show all $of',
      toggled: open,
      onTap: onTap,
      radius: BorderRadius.circular(99),
      color: open ? t.accentSoft : t.tile,
      side: BorderSide(color: t.lineStrong),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _pad),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              '+$count more',
              style: style.copyWith(color: open ? t.accent : t.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// One source. A file in Sources opens the passages the answer read from it in a sheet, when
/// the server sent them, or else lights up in Documents; a web
/// page an agent read opens in the browser; anything else, such as a file since removed, only
/// shows its title.
class _Citation extends StatelessWidget {
  const _Citation({
    required this.number,
    required this.citation,
    this.onPick,
    this.picked = false,
  });

  final int number;
  final Citation citation;

  /// What a tap does in place of opening the source, as picking it in the panel beside the chat.
  final VoidCallback? onPick;

  /// Whether the panel beside the chat shows this source as chosen.
  final bool picked;

  /// The name's style, but for the colour.
  static final nameStyle = Type.note(const Color(0x00000000));

  /// A chip's width around its name: its padding, number, icon and the gaps between them.
  static const frame = _padStart + _number + gap + _icon + gap + _padEnd;
  static const _padStart = 8.0;
  static const _padEnd = 12.0;
  static const _number = 17.0;
  static const _icon = 13.0;

  /// The room between its parts.
  static const gap = 6.0;

  /// The room between chips in a line, as House UI keeps neighbouring controls apart.
  static const apart = 8.0;

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
    final passages = present && citation.passages.isNotEmpty;
    final chip = Tappable(
      touchTarget: true,
      label: present || url == null
          ? 'Source $number: $title'
          : 'Source $number: $title, opens in the browser',
      tooltip: passages
          ? 'Passages read'
          : present
          ? 'Show in Documents'
          : url?.toString(),
      selected: onPick == null ? null : picked,
      onTap:
          onPick ??
          (passages
              ? () => scope.shell.togglePopup(citation)
              : present
              ? () => showCitedInDocuments(context, title)
              : url == null
              ? null
              : () => openLink(context, url)),
      radius: BorderRadius.circular(99),
      // A chip is the panel's colour, outlined, as the Lite prototype draws it. One that opens
      // nothing, as a file since removed, is fainter all through, not only in its number.
      color: picked ? t.accentSoft : t.tile,
      side: BorderSide(color: live ? t.lineStrong : t.line),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(_padStart, 0, _padEnd, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CitationNumber(number, live: live, diameter: _number),
              const SizedBox(width: gap),
              // What it is, as the boards mark it: a web page or a document.
              SizedBox.square(
                dimension: _icon,
                child: FittedBox(
                  child: AppIcon(
                    url != null ? 'globe' : 'doc',
                    size: IconSize.tiny,
                    color: live ? t.ink : t.muted,
                  ),
                ),
              ),
              const SizedBox(width: gap),
              Flexible(
                child: Text(
                  citedName(citation),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nameStyle.copyWith(color: live ? t.ink : t.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!passages || onPick != null) return chip;
    // Only a citation that opens a sheet follows the popup.
    return ShellPopup(
      popup: citation,
      title: 'Passages read',
      builder: (context, close) =>
          PassagesView(citation: citation, onClose: close),
      child: chip,
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
