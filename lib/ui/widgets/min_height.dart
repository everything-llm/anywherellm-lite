import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// [child] at the height it is given, or at [min] inside a scroll view when given less, as with
/// the keyboard up on a phone on its side. A field focused in it still scrolls into view.
///
/// The scroll view is always there, even when nothing needs to scroll: switching to it only
/// when the keyboard rises would rebuild [child], and with it drop what is typed and the
/// focus, which puts the keyboard away again.
class MinHeight extends StatelessWidget {
  const MinHeight({super.key, required this.min, required this.child});

  final double min;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      child: SizedBox(height: math.max(box.maxHeight, min), child: child),
    ),
  );
}
