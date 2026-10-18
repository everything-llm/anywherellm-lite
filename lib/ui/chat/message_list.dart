import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/chat.dart';
import '../../core/copy.dart';
import '../../core/prefs.dart';
import '../../core/shortcuts.dart';
import '../../core/server_models.dart';
import '../app_scope.dart';
import '../links.dart';
import '../icons.dart';
import '../layout.dart';
import '../state/chat_controller.dart';
import '../state/turn.dart';
import '../state/prefs_controller.dart';
import '../state/shell_controller.dart';
import '../state/sources_controller.dart';
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
import 'follow_ups.dart';
import 'shortcut_chip.dart';
import 'answer_menu.dart';
import 'generated_files.dart';
import 'passages_sheet.dart';
import 'speaker.dart';
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

  /// How far from the newest text the list must sit for the jump button to show.
  static const _jumpFrom = 48.0;

  /// Whether the list sits more than [_jumpFrom] from the newest text, as its last scroll or
  /// change of size left it.
  final _away = ValueNotifier(false);

  /// The newest turn's height as last laid out.
  final _newest = _Extent();

  @override
  void dispose() {
    _scroll.dispose();
    _away.dispose();
    super.dispose();
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
    final top = Align(
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
      ],
    );
  }

  /// The [i]th turn from the newest.
  Widget _turn(ChatController chat, List<Turn> turns, int i) {
    final scope = AppScope.of(context);
    final turn = turns[turns.length - 1 - i];
    final first = i == turns.length - 1;
    // Every turn is 14 from the one before.
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
            padding: EdgeInsets.only(top: first ? 0 : 16),
            child: Rise(
              child: turn.role == Role.user
                  ? turn.shortcutUse == null
                        ? _UserBubble(
                            turn.text,
                            attachments: turn.attachments,
                            onEdit: () => widget.onSuggest(turn.text),
                          )
                        : ListenableBuilder(
                            listenable: scope.prefs,
                            builder: (context, _) => _UserBubble(
                              turn.text,
                              attachments: turn.attachments,
                              shortcutUse: turn.shortcutUse,
                              hideShortcutPrompt: scope.prefs.prefs.isOn(
                                ChatSwitch.hideShortcutPrompts,
                              ),
                              onEdit: () => widget.onSuggest(turn.text),
                            ),
                          )
                  : _Answer(
                      turn,
                      retry: i == 0 ? _retryOf(chat) : null,
                      onMore: () => widget.onSuggest('/'),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The round button over the composer that scrolls the chat back to its newest text: 48 across
/// on [Tokens.panel], inside a [Tokens.line2] edge, floating on a shadow.
class _JumpButton extends StatelessWidget {
  const _JumpButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: t.shadow,
            blurRadius: 24,
            spreadRadius: -8,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Tappable(
        label: 'Jump to the newest message',
        tooltip: 'Jump to the newest message',
        onTap: onTap,
        shape: CircleBorder(side: BorderSide(color: t.line2)),
        color: t.panel,
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
  const _Empty({required this.workspace});

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
            child: Center(child: _hero(context, scope, sources, titleStyle)),
          ),
        );
      },
    );
  }

  Widget _hero(
    BuildContext context,
    AppScope scope,
    SourcesController sources,
    TextStyle titleStyle,
  ) {
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
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    // The chevron sits against the name, so it reads as part of what opens.
                    children: [
                      Flexible(
                        child: Text(
                          workspace,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                onTap: scope.shell.openSources,
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width - 32,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(
                          'doc',
                          size: IconSize.xs,
                          color: Tokens.of(context).muted,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Type.sans(
                              14,
                              color: Tokens.of(context).muted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AppIcon(
                          'chevron',
                          size: IconSize.tiny,
                          color: Tokens.of(context).muted,
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
    this.shortcutUse,
    this.hideShortcutPrompt = false,
    required this.onEdit,
  });

  final String text;

  /// The files sent with the question: a picture drawn small, any other by its name.
  final List<SentFile> attachments;
  final ShortcutUse? shortcutUse;
  final bool hideShortcutPrompt;

  /// Puts [text] back in the composer, to ask again as a new message.
  final VoidCallback onEdit;

  /// The bubble stands alone, at most 300 wide, as the Lite prototype draws it, and a long press
  /// on it is Edit.
  @override
  Widget build(BuildContext context) {
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

  Widget _bubble(BuildContext context) {
    final t = Tokens.of(context);
    final compact = hideShortcutPrompt ? shortcutUse : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.bubble,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact case final use?) ...[
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
              style: Type.note(t.muted),
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
  const _Answer(this.turn, {this.retry, this.onMore});

  final Turn turn;

  /// What More does in the follow-ups under the chat's last answer.
  final VoidCallback? onMore;

  /// Retry, on the chat's last answer only.
  final _Retry? retry;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: turn, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final split = splitReasoning(turn.text, streaming: turn.streaming);
    final failure = turn.streaming ? null : modelFailure(split.answer);
    final answered = split.answer.isNotEmpty && failure == null;
    // The caret ends the text being written where it can, and stands alone where it cannot.
    final inline = turn.streaming && answered && takesCaret(split.answer);
    // An answer cut short shows what came in the second ink, under why it stopped.
    final cut = !turn.streaming && turn.unfinished;
    const action = answerAction;
    // The red box asks again itself, so Retry does not show twice.
    final askAgain = turn.error != null && retry?.onPressed != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (failure != null)
          AlertBox(AlertKind.bad, 'The model did not answer', text: failure)
        else if (split.answer.isNotEmpty)
          AnswerBody(split.answer, muted: cut, caret: inline),
        // Until the first words, while a model's reasoning is hidden too, what it waits on.
        if (turn.streaming && split.answer.isEmpty)
          WaitLine(turn)
        else ...[
          if (turn.streaming && turn.status != null) _Status(turn.status!),
          if (turn.streaming && !inline)
            // The caret alone where the text cannot end with it, as in a code fence.
            const Padding(padding: EdgeInsets.only(top: 6), child: Caret()),
        ],
        if (turn.waiting) ...[
          const SizedBox(height: 10),
          AlertBox(
            AlertKind.info,
            'Still answering on the server',
            text:
                'The connection dropped. AnythingLLM keeps going, and the answer shows '
                'here once it is saved.',
            action: AppButton(
              'Check now',
              onPressed: () =>
                  unawaited(AppScope.of(context).chat.checkWaiting()),
            ),
          ),
        ],
        if (turn.error case final error?) ...[
          const SizedBox(height: 10),
          AlertBox(
            AlertKind.bad,
            'The answer stopped',
            text: error,
            action: askAgain
                ? AppButton('Ask again', onPressed: retry!.onPressed)
                : null,
          ),
        ],
        if (!turn.streaming && turn.citations.isNotEmpty) ...[
          const SizedBox(height: 8),
          _Citations(turn.citations),
        ],
        if (!turn.streaming && turn.files.isNotEmpty) ...[
          const SizedBox(height: 12),
          GeneratedFiles(turn.files),
        ],
        if (!turn.streaming && (answered || (retry != null && !askAgain))) ...[
          const SizedBox(height: 8),
          // The buttons are 44 wide, side by side, and the row starts 12 to the left, so the
          // first icon lines up with the text.
          Transform.translate(
            offset: const Offset(-12, 0),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (answered)
                  CopyButton(
                    split.answer,
                    tooltip: 'Copy answer',
                    box: action,
                    size: answerActionIcon,
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
                    size: answerActionIcon,
                  ),
                if (turn.metrics case final metrics?) AnswerMore(turn, metrics),
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
        // Under the chat's last answer, once it ran to its end.
        if (retry != null &&
            onMore != null &&
            answered &&
            !turn.streaming &&
            !turn.stopped &&
            !turn.unfinished &&
            turn.error == null)
          FollowUps(onMore: onMore!),
      ],
    );
  }
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
        box: answerAction,
        size: answerActionIcon,
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
/// the first three by name, then the rest folded into one "+N" chip that lists them all in a
/// sheet. A web page is named by its site.
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
        // The line is 44 tall around its chips, as the Lite prototype draws it.
        return ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: Alignment.centerLeft,
            heightFactor: 1,
            child: ClipRect(
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
            ),
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
    return Tappable(
      touchTarget: true,
      label: '$count more sources',
      toggled: open,
      onTap: onTap,
      radius: BorderRadius.circular(99),
      color: open ? t.sel : t.panel,
      side: BorderSide(color: t.edge),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              '+$count',
              style: Type.sans(13.5, color: open ? t.accent : t.ink2),
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
      onTap: passages
          ? () => scope.shell.togglePopup(citation)
          : present
          ? () {
              scope.shell.openSources();
              scope.sources.flash(title);
            }
          : url == null
          ? null
          : () => openLink(context, url.toString()),
      radius: BorderRadius.circular(99),
      // A chip is the panel's colour, outlined, as the Lite prototype draws it. One that opens
      // nothing, as a file since removed, is fainter all through, not only in its number.
      color: t.panel,
      side: BorderSide(color: live ? t.edge : t.line),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 36),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 12, 0),
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
                    style: Type.sans(13.5, color: live ? t.ink2 : t.muted),
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
        sheet: (context) => PassagesView(citation: citation, onClose: close),
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
