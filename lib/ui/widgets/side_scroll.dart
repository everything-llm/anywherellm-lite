import 'package:flutter/material.dart';

/// [child] scrolling sideways rather than widening what holds it, with its scrollbar shown under
/// it while it is wider, so a cut edge reads as more to scroll to. A scrollbar paints nothing
/// when [child] fits. Leave room for the bar at the bottom of [padding].
class SideScroll extends StatefulWidget {
  const SideScroll({super.key, this.padding, required this.child});

  final EdgeInsetsGeometry? padding;
  final Widget child;

  @override
  State<SideScroll> createState() => _SideScrollState();
}

class _SideScrollState extends State<SideScroll> {
  // A scrollbar that always shows needs its own controller: a sideways scroll view is never
  // the primary one.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _scroll,
    thumbVisibility: true,
    child: SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      child: widget.child,
    ),
  );
}
