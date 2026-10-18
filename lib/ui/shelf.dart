import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'home.dart';
import 'layout.dart';
import 'tokens.dart';
import 'widgets/phone_page.dart';
import 'widgets/rise.dart';

/// The chats as a shelf that slides in from the left over the chat, which shows dimmed
/// beside it, with Settings at its foot: the chat's menu button opens it, and tapping the dimmed
/// chat, a swipe to the left, Back or anything the shelf opens closes it.
class ChatsShelf extends StatefulWidget {
  const ChatsShelf({super.key});

  /// The shelf's share of the window's width, and the most it takes.
  static const fraction = 0.86;
  static const maxWidth = 420.0;

  @override
  State<ChatsShelf> createState() => _ChatsShelfState();
}

class _ChatsShelfState extends State<ChatsShelf>
    with SingleTickerProviderStateMixin {
  /// How far the shelf is out, from 0 (hidden at the left) to 1.
  late final _out = AnimationController(vsync: this);
  late final _slide = Tween(
    begin: const Offset(-1, 0),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _out, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    // The chat's field gives up the keyboard, which would cover the shelf.
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final slide = motion(context, const Duration(milliseconds: 220));
      slide == Duration.zero
          ? _out.value = 1
          : _out.animateTo(1, duration: slide);
    });
  }

  @override
  void dispose() {
    _out.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    final t = Tokens.of(context);
    const corner = BorderRadius.horizontal(
      right: Radius.circular(Sizes.composer),
    );
    return LayoutBuilder(
      builder: (context, box) => Stack(
        children: [
          Positioned.fill(
            child: FadeTransition(
              opacity: _out,
              child: Semantics(
                container: true,
                label: 'Close the chats',
                button: true,
                child: GestureDetector(
                  onTap: shell.closeShelf,
                  child: ColoredBox(color: t.scrim),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: math.min(
              box.maxWidth * ChatsShelf.fraction,
              ChatsShelf.maxWidth,
            ),
            child: SlideTransition(
              position: _slide,
              child: RepaintBoundary(
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if (details.velocity.pixelsPerSecond.dx < -300) {
                      shell.closeShelf();
                    }
                  },
                  // The shelf runs the window's full height, behind the bars, and keeps its
                  // rows clear of them. Its edge is ruled so it stands off the dimmed chat.
                  child: Material(
                    color: t.bg,
                    clipBehavior: Clip.antiAlias,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: corner,
                      side: BorderSide(color: t.line2),
                    ),
                    child: const SafeArea(
                      right: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: ChatsList()),
                          _SettingsFoot(),
                        ],
                      ),
                    ),
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

/// The shelf's foot: a row that opens Settings' list over the chat, under a rule.
class _SettingsFoot extends StatelessWidget {
  const _SettingsFoot();

  @override
  Widget build(BuildContext context) {
    final shell = AppScope.of(context).shell;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Tokens.of(context).line2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: NavRow(
          icon: 'gear',
          title: 'Settings',
          onTap: shell.openSettings,
        ),
      ),
    );
  }
}
