import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/copy.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/headline.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/phone_page.dart';
import '../widgets/tappable.dart';
import '../settings/settings_pages.dart';
import '../state/chat_controller.dart';
import '../state/shell_controller.dart';
import 'composer.dart';
import 'message_list.dart';
import 'sources_aside.dart';

/// The chat on screen: its header, its turns and the composer.
class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _draft = TextEditingController();
  final _focus = FocusNode();
  final _composer = GlobalKey<ComposerState>();
  late final _followed = FollowedSource(
    AppScope.of(context).chat,
    AppScope.of(context).shell.aside,
  );

  @override
  void dispose() {
    _draft.dispose();
    _focus.dispose();
    _followed.dispose();
    super.dispose();
  }

  void _edit(String text) => _composer.currentState?.edit(text);

  void _putBack(OnDeck item) => _composer.currentState?.putBack(item);

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final top = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Header(),
        ListenableBuilder(
          listenable: Listenable.merge([
            scope.chat,
            scope.prefs,
            scope.chat.unreachable,
          ]),
          builder: (context, _) {
            // A server that cannot be reached has the banner, in place of the read's failure.
            final unreachable =
                scope.chat.unreachable.value && scope.settings.configured;
            final notice = scope.chat.notice ?? scope.prefs.problem;
            // Why a link did not open stays until it is closed, or another chat or message.
            final link = scope.chat.linkNotice;
            if (!unreachable && notice == null && link == null) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: unreachable
                  ? const EdgeInsets.fromLTRB(16, 4, 16, 0)
                  : const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  if (unreachable) const _Unreachable(),
                  if (notice != null) AlertBox.notice(AlertKind.bad, notice),
                  if (link != null)
                    AlertBox.notice(
                      AlertKind.bad,
                      link,
                      onClose: scope.chat.closeLinkNotice,
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
    final chat = ClipRect(
      child: CustomMultiChildLayout(
        delegate: _chatLayout,
        children: [
          // The header keeps to the column the turns and the composer share, so on a wide
          // window its buttons line up with them.
          LayoutId(
            id: _Slot.top,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Sizes.column),
                child: top,
              ),
            ),
          ),
          LayoutId(
            id: _Slot.body,
            child: _Body(onEdit: _edit, onPutBack: _putBack),
          ),
          // Last, so it paints over the header when there is no room for both.
          LayoutId(
            id: _Slot.composer,
            child: Composer(key: _composer, draft: _draft, focus: _focus),
          ),
        ],
      ),
    );
    // On a wide window an answer's sources sit beside the chat. The chat keeps its place in the
    // row either way, so crossing the width keeps its state.
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: chat),
        if (Wide.split(context))
          // Under the header's height, so the header reads across the top of both.
          const Padding(
            padding: EdgeInsets.fromLTRB(Wide.gap - 16, Sizes.header, 16, 16),
            child: SizedBox(width: Wide.sourcesPanel, child: SourcesAside()),
          ),
      ],
    );
    return FollowedScope(notifier: _followed, child: row);
  }
}

/// The banner under the header while the server cannot be reached: what to check, the address,
/// Try again, which reads the workspaces at once, and Connection, which opens the address and
/// key. The chat stays readable and the message box stays open.
class _Unreachable extends StatelessWidget {
  const _Unreachable();

  // Const where the chat builds it, so it listens to the settings for the address it shows.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppScope.of(context).settings,
    builder: _build,
  );

  Widget _build(BuildContext context, Widget? _) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: t.tile,
          border: Border.all(color: t.tileEdge),
          borderRadius: BorderRadius.circular(24),
          boxShadow: t.raisedShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.sunken,
                    shape: BoxShape.circle,
                  ),
                  child: AppIcon(
                    'alert',
                    size: IconSize.normal,
                    color: t.danger,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Text(
                        'Can’t reach your AnythingLLM',
                        style: Type.body(t.ink, weight: FontWeight.w600),
                      ),
                      Text(
                        'Check that the computer is on and that this phone is on the '
                        'same network.',
                        style: Type.body(t.ink),
                      ),
                      if (scope.settings.connection case final server?)
                        Text(
                          server.baseUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.mono(13, color: t.muted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              spacing: 12,
              children: [
                Expanded(
                  child: ListenableBuilder(
                    listenable: scope.chat,
                    builder: (context, _) => AppButton(
                      'Try again',
                      primary: true,
                      compact: true,
                      onPressed: scope.chat.loading
                          ? null
                          : () => unawaited(scope.chat.load()),
                    ),
                  ),
                ),
                Expanded(
                  child: AppButton(
                    'Connection',
                    compact: true,
                    onPressed: () =>
                        scope.shell.openSettings(SettingsPage.connection),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _Slot { top, body, composer }

/// One layout for every build; it has no settings to change. Flutter's delegate base class has
/// no const constructor.
final _chatLayout = _ChatLayout();

/// The composer at its own height at the bottom, the header and notices at theirs at the top,
/// and the turns in whatever is left, down to nothing. With the keyboard up on a short screen
/// the header and the turns give way, never the field being typed in.
class _ChatLayout extends MultiChildLayoutDelegate {
  @override
  void performLayout(Size size) {
    final width = BoxConstraints.tightFor(width: size.width);
    // The composer is no taller than the window; what it holds above the field scrolls.
    final composer = layoutChild(
      _Slot.composer,
      BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        maxHeight: size.height,
      ),
    );
    final top = layoutChild(_Slot.top, width);
    final body = math.max(0.0, size.height - top.height - composer.height);
    layoutChild(
      _Slot.body,
      BoxConstraints.tightFor(width: size.width, height: body),
    );
    positionChild(_Slot.top, Offset.zero);
    positionChild(_Slot.body, Offset(0, top.height));
    positionChild(_Slot.composer, Offset(0, size.height - composer.height));
  }

  @override
  bool shouldRelayout(_ChatLayout oldDelegate) => false;
}

class _Body extends StatelessWidget {
  const _Body({required this.onEdit, required this.onPutBack});

  final ValueChanged<String> onEdit;
  final ValueChanged<OnDeck> onPutBack;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        scope.chat,
        scope.settings,
        scope.chat.unreachable,
      ]),
      builder: (context, _) {
        final chat = scope.chat;
        if (chat.active != null) {
          return MessageList(onEdit: onEdit, onPutBack: onPutBack);
        }
        // The banner says why there is nothing to show, so no empty state says otherwise.
        if (scope.settings.configured && chat.unreachable.value) {
          return const SizedBox.shrink();
        }
        final (title, text) = !scope.settings.configured
            ? (
                'Welcome to AnywhereLLM',
                'Set up your AnythingLLM server in Settings to begin.',
              )
            : chat.loading
            ? ('Loading…', '')
            : (
                'No workspaces yet',
                'Make one with New workspace, under the workspace\'s name at the top of the chats.',
              );
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Headline(title, textAlign: TextAlign.center),
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: Type.body(t.muted),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The chat's header: Chats, which opens the Chats shelf, the workspace and its documents over the chat's
/// name, which opens the chat's sheet, or on a new chat the workspace's settings, then New chat.
/// Beside the sidebar, which has both, it holds the name alone.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.chat, scope.sources]),
      builder: (context, _) {
        final chat = scope.chat;
        final workspace = chat.active;
        final thread = chat.thread;
        final docs = scope.sources.onCount;
        final sidebar = Wide.sidebarShown(context);
        // The name and the workspace's line wrap rather than lose their ends.
        final title = Text(
          workspace == null ? 'AnywhereLLM' : chat.title,
          style: Type.title(t.ink),
        );
        final heading = workspace == null
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Semantics(header: true, child: title),
              )
            : Tappable(
                label: thread != null
                    ? '${chat.title}. Rename, pin or delete this chat'
                    : '${workspace.name}. Open workspace settings',
                onTap: () => thread != null
                    ? scope.shell.openChatSheet(thread)
                    : scope.shell.showPane(Pane.files),
                radius: BorderRadius.circular(Sizes.small),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        spacing: 4,
                        children: [
                          Flexible(
                            child: Text(
                              '${workspace.name} · '
                              '${plural(docs, 'doc', 'docs')} in use',
                              style: Type.caption(
                                t.ink,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                          AppIcon('chevron', size: IconSize.tiny, color: t.ink),
                        ],
                      ),
                      title,
                    ],
                  ),
                ),
              );
        if (sidebar) {
          return ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Sizes.header),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(alignment: Alignment.centerLeft, child: heading),
            ),
          );
        }
        return PhonePageHeader(
          back: 'Chats',
          backIcon: 'menu',
          onBack: scope.shell.openShelf,
          heading: heading,
          action: workspace == null
              ? null
              : IconBtn.header(
                  'plus',
                  tooltip: 'New chat',
                  onPressed: chat.newChat,
                ),
        );
      },
    );
  }
}
