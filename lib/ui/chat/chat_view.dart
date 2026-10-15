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
import '../state/shell_controller.dart';
import 'composer.dart';
import 'message_list.dart';

/// The chat on screen: its header, its turns and the composer.
class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _draft = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _draft.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _suggest(String text) {
    _draft.text = text;
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final top = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Header(),
        ListenableBuilder(
          listenable: Listenable.merge([scope.chat, scope.prefs]),
          builder: (context, _) {
            final notices = [
              ?(scope.chat.problem ?? scope.prefs.problem),
              ?scope.chat.linkNotice,
            ];
            if (notices.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  for (final n in notices) AlertBox.notice(AlertKind.bad, n),
                ],
              ),
            );
          },
        ),
      ],
    );
    return ClipRect(
      child: CustomMultiChildLayout(
        delegate: _chatLayout,
        children: [
          LayoutId(id: _Slot.top, child: top),
          LayoutId(
            id: _Slot.body,
            child: _Body(onSuggest: _suggest),
          ),
          // Last, so it paints over the header when there is no room for both.
          LayoutId(
            id: _Slot.composer,
            child: Composer(draft: _draft, focus: _focus),
          ),
        ],
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
    final composer = layoutChild(_Slot.composer, width);
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
  const _Body({required this.onSuggest});

  final ValueChanged<String> onSuggest;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.chat, scope.settings]),
      builder: (context, _) {
        final chat = scope.chat;
        if (chat.active != null) return MessageList(onSuggest: onSuggest);
        final (title, text) = !scope.settings.configured
            ? (
                'Welcome to AnywhereLLM',
                'Set up your AnythingLLM server in Settings to begin.',
              )
            : chat.loading
            ? ('Loading…', '')
            : (
                'No workspaces yet',
                'Make one with New workspace, under the workspace\'s name at the top of the Chats tab.',
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
                    style: Type.sans(15, color: t.muted),
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
        final title = Text(
          workspace == null ? 'AnywhereLLM' : chat.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Type.sans(18, weight: FontWeight.w600, color: t.ink),
        );
        return PhonePageHeader(
          back: 'Chats',
          backIcon: 'menu',
          onBack: scope.shell.openShelf,
          heading: workspace == null
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Type.sans(
                                  12.5,
                                  weight: FontWeight.w700,
                                  color: t.muted,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            AppIcon(
                              'chevron',
                              size: IconSize.tiny,
                              color: t.muted,
                            ),
                          ],
                        ),
                        title,
                      ],
                    ),
                  ),
                ),
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
