import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons.dart';
import '../layout.dart';
import '../tokens.dart';
import '../type.dart';
import 'tappable.dart';

/// [child], with the menu [menu] builds under it while [open], or over it when [above], level
/// with its left edge, or its right one when [alignRight], and moved by [offset] when given. A
/// tap outside both, or Esc, calls [onClose]. The menu is drawn in the app's overlay and
/// inherits what [child] does.
class PopupAnchor extends StatefulWidget {
  const PopupAnchor({
    super.key,
    required this.open,
    required this.onClose,
    required this.menu,
    required this.child,
    this.alignRight = false,
    this.above = false,
    this.width,
    this.offset,
    this.group,
  });

  final bool open;
  final VoidCallback onClose;
  final WidgetBuilder menu;
  final Widget child;
  final bool alignRight;
  final bool above;

  /// The menu's width, or null for its own.
  final double? width;

  /// Where the menu sits from [child]'s edge, in place of a small gap above or below it.
  final Offset? offset;

  /// The tap group the menu belongs to, for a part of [child] in a [TapRegion] of it to tap as
  /// inside the menu; without it, the whole of [child] does.
  final Object? group;

  @override
  State<PopupAnchor> createState() => _PopupAnchorState();
}

class _PopupAnchorState extends State<PopupAnchor> {
  // Always showing: the overlay draws nothing while the menu is closed, so [PopupAnchor.open]
  // is the one place that says whether it is.
  final _portal = OverlayPortalController()..show();
  final _link = LayerLink();

  /// [child] and the menu tap as one: a tap on [child] is not a tap outside the menu.
  final _own = Object();

  Object get _group => widget.group ?? _own;

  @override
  Widget build(BuildContext context) {
    final target = CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _overlay,
        child: widget.child,
      ),
    );
    return widget.group == null
        ? TapRegion(groupId: _own, child: target)
        : target;
  }

  Widget _overlay(BuildContext context) {
    if (!widget.open) return const SizedBox.shrink();
    final right = widget.alignRight;
    final above = widget.above;
    final near = Alignment(right ? 1 : -1, above ? 1 : -1);
    return CompositedTransformFollower(
      link: _link,
      targetAnchor: Alignment(right ? 1 : -1, above ? -1 : 1),
      followerAnchor: near,
      offset: widget.offset ?? Offset(0, above ? -4 : 6),
      showWhenUnlinked: false,
      child: Align(
        alignment: near,
        child: TapRegion(
          groupId: _group,
          onTapOutside: (_) => widget.onClose(),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
            },
            child: Focus(
              autofocus: true,
              child: SizedBox(width: widget.width, child: widget.menu(context)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A menu's card: [children] in a column on the panel, raised over what is under it.
class AppMenu extends StatelessWidget {
  const AppMenu({super.key, required this.label, required this.children});

  /// What a screen reader calls the menu.
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Material(
      color: t.panel,
      elevation: 8,
      shadowColor: t.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Sizes.menu),
        side: BorderSide(color: t.line),
      ),
      child: Semantics(
        container: true,
        label: label,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// A thin line between groups of an [AppMenu]'s items.
class MenuDivider extends StatelessWidget {
  const MenuDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: Container(height: 1, color: Tokens.of(context).line2),
  );
}

/// One of a menu's actions: an [icon] in its own column, so labels line up with or without
/// one, and the label in the bad colour when [danger], the accent when [accent].
class AppMenuItem extends StatelessWidget {
  const AppMenuItem(
    this.label, {
    super.key,
    required this.onTap,
    this.icon,
    this.danger = false,
    this.accent = false,
  });

  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final bool danger;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = ScreenClass.ofContext(context).isPhone;
    final color = danger
        ? t.badfg
        : accent
        ? t.accent
        : t.ink;
    return Tappable(
      label: label,
      onTap: onTap,
      radius: BorderRadius.circular(Sizes.row),
      dimWhenDisabled: 0.4,
      child: SizedBox(
        height: phone ? 48 : 38,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: icon == null
                    ? null
                    : AppIcon(icon!, size: IconSize.xs, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Type.sans(phone ? 15 : 14, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
