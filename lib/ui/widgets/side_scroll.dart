import 'package:flutter/material.dart';

import '../tokens.dart';

/// [child] scrolling sideways rather than widening what holds it, with its scrollbar shown under
/// it while it is wider, so a cut edge reads as more to scroll to. A scrollbar paints nothing
/// when [child] fits. The bar is thin, in the theme's strong line colour, the same on every
/// platform. Leave room for it at the bottom of [padding].
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
  Widget build(BuildContext context) => RawScrollbar(
    controller: _scroll,
    thumbVisibility: true,
    thickness: 3,
    radius: const Radius.circular(1.5),
    thumbColor: Tokens.of(context).lineStrong,
    crossAxisMargin: 4,
    mainAxisMargin: 8,
    child: SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      child: widget.child,
    ),
  );
}
