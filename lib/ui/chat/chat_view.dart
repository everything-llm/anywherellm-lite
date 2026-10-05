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
    return Column(
      children: [
        _Header(showMenu: widget.showMenu),
        ListenableBuilder(
          listenable: Listenable.merge([scope.chat, scope.prefs]),
          builder: (context, _) {
            final problem = scope.chat.problem ?? scope.prefs.problem;
            if (problem == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: AlertBox(AlertKind.bad, problem.title, text: problem.text),
            );
          },
        ),
        Expanded(child: _Body(onSuggest: _suggest)),
        Composer(draft: _draft, focus: _focus),
      ],
    );
  }
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
                'Welcome to Nilson',
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
                  ? const [TextSpan(text: 'Nilson')]
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
                    trailing: NilsBadge(
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
              NilsIcon(icon, size: IconSize.xs, color: t.ink),
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
