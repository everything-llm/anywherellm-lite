import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import '../widgets/headline.dart';
import '../widgets/basics.dart';
import '../widgets/buttons.dart';
import '../widgets/controls.dart';
import '../widgets/pane_header.dart';
import '../widgets/tappable.dart';
import '../state/chat_controller.dart';
import '../state/shell_controller.dart';
import 'browser_chip.dart';
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
                'Sign in to your AnythingLLM server in Settings to begin.',
              )
            : chat.loading
            ? ('Loading…', '')
            : (
                'No workspaces yet',
                'Make one with New workspace, in the workspace menu at the top of the sidebar.',
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

class _Header extends StatelessWidget {
  const _Header({required this.showMenu});

  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    if (ScreenClass.ofContext(context).isPhone) return const _PhoneHeader();
    return ListenableBuilder(
      listenable: Listenable.merge([scope.chat, scope.sources, scope.shell]),
      builder: (context, _) {
        final chat = scope.chat;
        final workspace = chat.active;
        final title = PaneHeader.chatTitleStyle(context);
        // A phone names the workspace small over the chat, and refreshes with a pull down on
        // the chat rather than a button.
        final phone = ScreenClass.ofContext(context).isPhone;
        return PaneHeader(
          showMenu: showMenu,
          onMenu: scope.shell.toggleSide,
          title: workspace == null
              ? Text(
                  'AnywhereLLM',
                  style: title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : phone
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Type.sans(12, color: t.muted, height: 1.3),
                    ),
                    Text(
                      chat.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: title.copyWith(fontSize: 16),
                    ),
                  ],
                )
              : Text.rich(
                  TextSpan(
                    style: title,
                    children: [
                      TextSpan(
                        text: workspace.name,
                        style: title.copyWith(
                          color: t.muted,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      TextSpan(
                        text: ' / ',
                        style: title.copyWith(
                          color: t.fade,
                          fontWeight: FontWeight.w400,
                        ),
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
                  // A phone's buttons sit side by side, as the design canvas draws them.
                  SizedBox(width: phone ? 4 : 12),
                  if (!phone)
                    _HeaderButton(
                      label: 'Refresh',
                      heard: 'Read this chat again from the server',
                      icon: 'refresh',
                      compact: true,
                      onTap: chat.refreshing ? null : chat.refresh,
                    ),
                  // New chat sits at the top of the sidebar while it is in the layout.
                  if (showMenu) ...[
                    if (!phone) const SizedBox(width: 8),
                    _HeaderButton(
                      label: 'New chat',
                      icon: 'plus',
                      compact: compact,
                      onTap: chat.newChat,
                    ),
                  ],
                  _BrowserButton(compact: compact),
                  SizedBox(width: phone ? 2 : 8),
                  _HeaderButton(
                    label: 'Documents',
                    heard: 'Documents, ${scope.sources.onCount} on',
                    icon: 'doc',
                    compact: compact,
                    pressed: scope.shell.sourcesOpen,
                    onTap: scope.shell.toggleSources,
                    trailing: AppBadge(
                      compact
                          ? '${scope.sources.onCount}'
                          : '${scope.sources.onCount} on',
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

/// A phone's header: the menu, the workspace and its documents over the chat's name, which
/// opens the chat's sheet, or on a new chat the workspace's settings, then the browser while the
/// chat has one and New chat.
class _PhoneHeader extends StatelessWidget {
  const _PhoneHeader();

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([scope.chat, scope.sources]),
      builder: (context, _) {
        final chat = scope.chat;
        final workspace = chat.active;
        final thread = chat.activeThread == null
            ? null
            : chat
                  .threadsOf(workspace?.slug ?? '')
                  .where((c) => c.slug == chat.activeThread)
                  .firstOrNull;
        final docs = scope.sources.onCount;
        final title = Text(
          workspace == null ? 'AnywhereLLM' : chat.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Type.sans(18, weight: FontWeight.w600, color: t.ink),
        );
        return SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              spacing: 4,
              children: [
                IconBtn(
                  'hamburger',
                  tooltip: 'Workspaces',
                  box: 48,
                  filled: true,
                  size: IconSize.small,
                  onPressed: scope.shell.toggleSide,
                ),
                Expanded(
                  child: workspace == null
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
                          radius: BorderRadius.circular(12),
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
                                        '${docs == 1 ? '1 doc' : '$docs docs'} in use',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Type.sans(
                                          12.5,
                                          color: t.muted,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                    AppIcon(
                                      'down',
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
                ),
                if (workspace != null) ...[
                  const _BrowserButton(compact: true),
                  IconBtn(
                    'plus',
                    tooltip: 'New chat',
                    box: 48,
                    filled: true,
                    size: IconSize.small,
                    onPressed: chat.newChat,
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

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.pressed,
    this.trailing,
    this.compact = false,
    this.heard,
  });

  final String label;

  /// What a screen reader hears in place of [label], when it says more.
  final String? heard;
  final String icon;

  /// Null while the button can do nothing.
  final VoidCallback? onTap;
  final bool? pressed;
  final Widget? trailing;

  /// Only the icon and [trailing] show, for a phone's narrow header. [label] is still heard.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    // On a phone an icon alone sits in a 36 px square, and one with a count is padded 6, as
    // the design canvas draws them.
    final tight = compact && ScreenClass.ofContext(context).isPhone;
    final gap = tight ? 6.0 : 7.0;
    return Tappable(
      touchTarget: true,
      label: heard ?? label,
      tooltip: compact ? label : null,
      toggled: pressed,
      onTap: onTap,
      radius: BorderRadius.circular(Sizes.row),
      color: pressed == true ? t.hover : null,
      child: Container(
        height: 36,
        constraints: BoxConstraints(minWidth: tight ? 36 : 0),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: tight ? 6 : 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: IconSize.xs, color: compact ? t.ink2 : t.ink),
            if (!compact) ...[
              SizedBox(width: gap),
              Text(
                label,
                style: Type.sans(14, weight: FontWeight.w500, color: t.ink),
              ),
            ],
            if (trailing != null) ...[SizedBox(width: gap), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Browser in the header, while the chat on screen has used the everythingllm browser
/// ([ChatController.usedBrowser]): it shows and hides the browser beside the chat, and pulses
/// while the agent is using it. It reads the running answer itself, which notifies on each
/// chunk where the controller does not.
class _BrowserButton extends StatelessWidget {
  const _BrowserButton({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => BrowserStateBuilder(builder: _build);

  Widget _build(BuildContext context, Turn? running) {
    final scope = AppScope.of(context);
    final shell = scope.shell;
    if (!scope.chat.usedBrowser && scope.browser.tab == null) {
      return const SizedBox.shrink();
    }
    final browsing =
        (running?.browsing ?? false) || (scope.browser.tab?.working ?? false);
    // A phone's header buttons are round, with the dot at the button's corner.
    if (ScreenClass.ofContext(context).isPhone) {
      return Stack(
        children: [
          IconBtn(
            'globe',
            tooltip: browsing ? 'Browser, in use now' : 'Browser',
            box: 48,
            filled: true,
            active: shell.browserOpen,
            size: IconSize.small,
            onPressed: shell.browserOpen
                ? shell.closeBrowser
                : shell.showBrowser,
          ),
          if (browsing) const Positioned(top: 8, right: 8, child: _Pulse()),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: _HeaderButton(
        label: 'Browser',
        heard: browsing ? 'Browser, in use now' : 'Browser',
        icon: 'globe',
        compact: compact,
        pressed: shell.browserOpen,
        onTap: shell.browserOpen ? shell.closeBrowser : shell.showBrowser,
        trailing: browsing ? const _Pulse() : null,
      ),
    );
  }
}

/// A dot that pulses, or holds still where the system asks for reduced motion.
class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    lowerBound: 0.35,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _controller,
    child: Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Tokens.of(context).accent,
        shape: BoxShape.circle,
      ),
    ),
  );
}
