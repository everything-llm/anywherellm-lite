import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons.dart';
import '../tokens.dart';
import '../type.dart';
import 'buttons.dart';
import 'rise.dart';

/// How tall a [SheetFrame] stands: [tall] fills the screen but for [SheetFrame.gap] above it,
/// and [fit] takes the height of what it holds, at most [SheetFrame.maxFraction] of the screen.
enum SheetHeight { tall, fit }

/// A sheet over the chat on a phone, filling what it is given: the scrim, which closes it when
/// tapped, and the sheet itself at the bottom, under a drag handle, with [title], the line
/// [about] under it, [actions] and Close, then [child]. Dragging the handle or the header down
/// past 120 px, or flinging it, closes it; a shorter drag puts it back.
///
/// [child] is laid out under the header in what is left: a [SheetHeight.tall] sheet gives it a
/// fixed height, so a scroll view fills it; a [SheetHeight.fit] sheet gives it a loose one.
class SheetFrame extends StatefulWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
    this.about,
    this.actions = const [],
    this.height = SheetHeight.fit,
    this.maxFraction = 0.9,
    this.live = false,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 24),
  });

  final String title;
  final String? about;
  final VoidCallback onClose;
  final Widget child;

  /// Buttons before Close, such as one that opens the sheet's page elsewhere.
  final List<Widget> actions;
  final SheetHeight height;

  /// The most of the screen a [SheetHeight.fit] sheet takes.
  final double maxFraction;

  /// Whether [about] is read out when it changes.
  final bool live;

  /// Around [child].
  final EdgeInsets padding;

  /// The room left above a [SheetHeight.tall] sheet, where the chat shows through the scrim.
  static const gap = 72.0;

  @override
  State<SheetFrame> createState() => _SheetFrameState();
}

class _SheetFrameState extends State<SheetFrame>
    with SingleTickerProviderStateMixin {
  /// How far the sheet has been dragged down, or still has to rise as it opens.
  late final _offset = AnimationController.unbounded(vsync: this);

  /// Whether the sheet's first rise has been started.
  bool _rose = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rose) return;
    _rose = true;
    final rise = motion(context, const Duration(milliseconds: 220));
    if (rise == Duration.zero) return;
    _offset.value = 160;
    _offset.animateTo(0, duration: rise, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _dragged(DragUpdateDetails details) {
    _offset.stop();
    _offset.value = math.max(0, _offset.value + details.delta.dy);
  }

  void _let(DragEndDetails details) {
    if (_offset.value > 120 || details.velocity.pixelsPerSecond.dy > 700) {
      widget.onClose();
    } else {
      _offset.animateTo(
        0,
        duration: motion(context, const Duration(milliseconds: 180)),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final tall = widget.height == SheetHeight.tall;
    final header = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _dragged,
      onVerticalDragEnd: _let,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: t.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          SheetHeader(
            title: widget.title,
            about: widget.about,
            live: widget.live,
            actions: widget.actions,
            onClose: widget.onClose,
            divided: tall,
          ),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final most = tall
            ? math.max(0.0, box.maxHeight - SheetFrame.gap)
            : box.maxHeight * widget.maxFraction;
        final sheet = Semantics(
          container: true,
          explicitChildNodes: true,
          label: widget.title,
          child: Container(
            constraints: BoxConstraints(maxHeight: most),
            height: tall ? most : null,
            decoration: BoxDecoration(
              color: t.panel,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              boxShadow: [
                BoxShadow(
                  color: t.shadow,
                  blurRadius: 40,
                  spreadRadius: -12,
                  offset: const Offset(0, -12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Flexible(
                  fit: tall ? FlexFit.tight : FlexFit.loose,
                  child: Padding(padding: widget.padding, child: widget.child),
                ),
              ],
            ),
          ),
        );
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onClose,
                child: ColoredBox(color: t.scrim),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedBuilder(
                animation: _offset,
                builder: (context, sheet) => Transform.translate(
                  offset: Offset(0, _offset.value),
                  child: sheet,
                ),
                child: sheet,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A sheet's header: [title] at 19, the line [about] under it, [actions] and a 44 px Close, with
/// a rule under it when [divided].
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.about,
    this.live = false,
    this.actions = const [],
    this.divided = false,
  });

  final String title;
  final String? about;
  final bool live;
  final List<Widget> actions;
  final VoidCallback onClose;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(24, 10, 12, divided ? 10 : 8),
      decoration: divided
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: t.line2)),
            )
          : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sans(
                      19,
                      weight: FontWeight.w600,
                      color: t.ink,
                      height: 1.3,
                    ),
                  ),
                ),
                if (about case final about?)
                  Semantics(
                    liveRegion: live,
                    child: Text(
                      about,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Type.sans(13.5, color: t.muted, height: 1.45),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          ...actions,
          IconBtn(
            'close',
            tooltip: 'Close',
            box: 44,
            filled: true,
            size: IconSize.small,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// [child], with what [overlay] builds over the whole window while [open]. The overlay
/// inherits from where [child] is, so it reads the app's scope. Its place in the window's
/// overlay is always taken and empty while closed, since a portal cannot be shown or hidden
/// while the tree builds.
class OverlayWhile extends StatefulWidget {
  const OverlayWhile({
    super.key,
    required this.open,
    required this.overlay,
    required this.child,
  });

  final bool open;
  final WidgetBuilder overlay;
  final Widget child;

  @override
  State<OverlayWhile> createState() => _OverlayWhileState();
}

class _OverlayWhileState extends State<OverlayWhile> {
  final _portal = OverlayPortalController()..show();

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _portal,
    overlayChildBuilder: (context) =>
        widget.open ? widget.overlay(context) : const SizedBox.shrink(),
    child: widget.child,
  );
}

/// [child], with a [SheetFrame] over the whole window while [open], holding what [sheet]
/// builds under [title]: the phone's form of a popup, such as an answer's More menu. Esc, the
/// scrim, Close and a drag down call [onClose]; Back reaches the shell, which closes the popup
/// open.
class PopupSheet extends StatelessWidget {
  const PopupSheet({
    super.key,
    required this.open,
    required this.onClose,
    required this.title,
    required this.sheet,
    required this.child,
    this.maxFraction = 0.9,
  });

  final bool open;
  final VoidCallback onClose;
  final String title;
  final WidgetBuilder sheet;
  final Widget child;
  final double maxFraction;

  @override
  Widget build(BuildContext context) => OverlayWhile(
    open: open,
    overlay: (context) => ModalSheet(
      title: title,
      onClose: onClose,
      maxFraction: maxFraction,
      child: Builder(builder: sheet),
    ),
    child: child,
  );
}

/// A [SheetFrame] over what holds it, under [title], that Esc closes as its scrim, Close and a
/// drag down do: the body of a [PopupSheet], and of a sheet the shell shows over the window.
/// It takes the focus unless [autofocus] is false, as when a field in it takes it instead.
class ModalSheet extends StatelessWidget {
  const ModalSheet({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
    this.maxFraction = 0.9,
    this.autofocus = true,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;
  final double maxFraction;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): onClose},
    child: Focus(
      autofocus: autofocus,
      child: SafeArea(
        child: SheetFrame(
          title: title,
          onClose: onClose,
          maxFraction: maxFraction,
          child: child,
        ),
      ),
    ),
  );
}
