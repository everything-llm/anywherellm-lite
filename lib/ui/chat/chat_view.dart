import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/basics.dart';
import '../widgets/controls.dart';
import '../widgets/pane_header.dart';
import '../widgets/tappable.dart';
import 'composer.dart';
import 'message_list.dart';

/// The chat on screen: its header, its turns and the composer.
class ChatView extends StatefulWidget {
  const ChatView({super.key, required this.showMenu});

  /// Whether the header has a button to open the sidebar drawer.
  final bool showMenu;

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
        _Header(showMenu: widget.showMenu),
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
                  for (final n in notices)
                    AlertBox(AlertKind.bad, n.title, text: n.text),
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
                'Add your AnythingLLM key in Settings to begin.',
              )
            : chat.loading
            ? ('Loading…', '')
            : (
                'No workspaces yet',
                'Make one with + beside Workspaces in the sidebar.',
              );
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Type.serif(32, color: t.ink),
                ),
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

class _Header extends StatelessWidget {
  const _Header({required this.showMenu});

  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.chat, scope.sources, scope.shell]),
      builder: (context, _) {
        final chat = scope.chat;
        final workspace = chat.active;
        final title = PaneHeader.titleStyle(context);
        return PaneHeader(
          showMenu: showMenu,
          onMenu: scope.shell.toggleSide,
          title: Text.rich(
            TextSpan(
              style: title,
              children: workspace == null
                  ? const [TextSpan(text: 'AnywhereLLM')]
                  : [
                      TextSpan(
                        text: workspace.name,
                        style: title.copyWith(color: t.muted),
                      ),
                      TextSpan(
                        text: ' / ',
                        style: title.copyWith(color: t.fade),
                      ),
                      TextSpan(text: chat.title),
                    ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: workspace == null
              ? null
              : (compact) => [
                  const SizedBox(width: 12),
                  _HeaderButton(
                    label: 'New chat',
                    icon: 'plus',
                    compact: compact,
                    onTap: chat.newChat,
                  ),
                  const SizedBox(width: 8),
                  _HeaderButton(
                    label: 'Sources',
                    icon: 'doc',
                    compact: compact,
                    pressed: scope.shell.sourcesOpen,
                    onTap: scope.shell.toggleSources,
                    trailing: AppBadge(
                      '${scope.sources.onCount}',
                      kind: BadgeKind.accent,
                      pill: true,
                    ),
                  ),
                ],
        );
      },
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.pressed,
    this.trailing,
    this.compact = false,
  });

  final String label;
  final String icon;
  final VoidCallback onTap;
  final bool? pressed;
  final Widget? trailing;

  /// Only the icon and [trailing] show, for a phone's narrow header. [label] is still heard.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tappable(
      label: label,
      tooltip: compact ? label : null,
      toggled: pressed,
      onTap: onTap,
      radius: BorderRadius.circular(9),
      color: pressed == true ? t.hover : t.panel,
      side: BorderSide(color: t.line),
      child: SizedBox(
        height: 36,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: IconSize.xs, color: t.ink),
              if (!compact) ...[
                const SizedBox(width: 7),
                Text(
                  label,
                  style: Type.sans(14, weight: FontWeight.w500, color: t.ink),
                ),
              ],
              if (trailing != null) ...[const SizedBox(width: 7), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
