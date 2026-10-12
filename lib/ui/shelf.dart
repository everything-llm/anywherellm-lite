import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'home.dart';
import 'tokens.dart';
import 'widgets/rise.dart';

/// The Chats tab as a shelf that slides in from the left over the chat, which shows dimmed
/// beside it: the chat's menu button opens it, and tapping the dimmed chat, a swipe to the
/// left, Back or anything the shelf opens closes it.
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

  /// Whether the first slide in has been started.
  bool _slid = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_slid) return;
    _slid = true;
    final slide = motion(context, const Duration(milliseconds: 220));
    if (slide == Duration.zero) {
      _out.value = 1;
    } else {
      _out.animateTo(1, duration: slide, curve: Curves.easeOut);
    }
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
    return LayoutBuilder(
      builder: (context, box) {
        final width = math.min(
          box.maxWidth * ChatsShelf.fraction,
          ChatsShelf.maxWidth,
        );
        return AnimatedBuilder(
          animation: _out,
          builder: (context, child) => Stack(
            children: [
              Positioned.fill(
                child: Semantics(
                  label: 'Close the chats',
                  button: true,
                  child: GestureDetector(
                    onTap: shell.closeShelf,
                    child: ColoredBox(
                      color: t.scrim.withValues(alpha: t.scrim.a * _out.value),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -width * (1 - _out.value),
                top: 0,
                bottom: 0,
                width: width,
                child: child!,
              ),
            ],
          ),
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              if (details.velocity.pixelsPerSecond.dx < -300) {
                shell.closeShelf();
              }
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.bg,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: t.shadow,
                    blurRadius: 40,
                    spreadRadius: -12,
                    offset: const Offset(12, 0),
                  ),
                ],
              ),
              child: const ClipRRect(
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(28),
                ),
                child: ChatsTab(),
              ),
            ),
          ),
        );
      },
    );
  }
}
